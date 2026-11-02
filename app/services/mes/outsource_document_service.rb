# 从委外加工单生成三张库存单：发料 / 产品入库 / 退料。
#
# 为什么集中在一个服务里：这三张单的数量不是人随手填的，是从加工单算出来的——
#   发料＝标准用量 − 已发；入库倒冲＝按实收数量反推的标准用量；退料≤加工厂手上剩的。
# 算错一次，委外仓的结存就从此对不上（生产上那四个委外仓期初之后再没动过，
# 正是因为根本没有单据能动它）。
class Mes::OutsourceDocumentService
  class Error < StandardError; end

  def initialize(order:, actor: nil)
    @order = order
    @account = order.account
    @actor = actor
  end

  # 委外发料单：原料仓 → 委外仓。
  # rows 不传则按「还没发的标准用量」整单带出；传了就按传的来（允许分批发）。
  def build_issue(rows: nil)
    lines = rows.presence || default_issue_rows
    raise Error, '没有要发的料' if lines.blank?

    # 整单兜底发料仓：行上没写仓库时用它（见 post_transfer_item）。
    # 每行可以各自指定自己的仓——同一张单的料未必都在一个仓。
    entry = new_entry('OUTSOURCE_ISSUE', from_warehouse_id: default_raw_warehouse_id,
                                         to_warehouse_id: outsource_warehouse_id!)
    lines.each { |row| entry.stock_entry_items.build(material_item_attrs(row)) }
    entry.tap(&:save!)
  end

  # 委外产品入库单：产出进成品仓(+)，同时按标准用量倒冲委外仓的料(-)。
  # qty = 这次实收多少台。倒冲量按**实收**算，不是按整单——收一半就只扣一半的料。
  def build_receipt(qty:, to_warehouse_id: nil)
    received = qty.to_d
    raise Error, '入库数量要大于 0' if received <= 0
    raise Error, "超出未收数量（还差 #{@order.remaining_qty}）" if received > @order.remaining_qty

    entry = new_entry('OUTSOURCE_RECEIPT', from_warehouse_id: outsource_warehouse_id!,
                                           to_warehouse_id: to_warehouse_id || @order.to_warehouse_id)
    raise Error, '没指定产出入哪个仓' if entry.to_warehouse_id.nil?

    entry.stock_entry_items.build(product_item_attrs(received, entry.to_warehouse_id))
    backflush_rows(received).each { |attrs| entry.stock_entry_items.build(attrs) }
    entry.tap(&:save!)
  end

  # 委外退料单：委外仓 → 原料仓 / 不良品仓。
  # rows: [{ material_id:, qty:, to_warehouse_id: }]。超过「加工厂手上还剩的」直接拦。
  def build_return(rows:, to_warehouse_id:)
    raise Error, '没有要退的料' if rows.blank?
    raise Error, '没指定退回哪个仓' if to_warehouse_id.blank?

    entry = new_entry('OUTSOURCE_RETURN', from_warehouse_id: outsource_warehouse_id!,
                                          to_warehouse_id: to_warehouse_id)
    rows.each do |row|
      material = find_material(row[:material_id])
      ensure_returnable!(material, row[:qty].to_d)
      # 退料的发出仓是**委外仓**（entry.from_warehouse_id），不是这颗料当初的发料仓——
      # 行上带了 warehouse_id 的话 post_transfer_item 会拿它当发出仓，
      # 变成「从原料仓扣、又加回原料仓」，两个仓都没动（2026-10-31 实测踩到）。
      entry.stock_entry_items.build(
        material_item_attrs(material: material, qty: row[:qty]).merge(warehouse_id: nil)
      )
    end
    entry.tap(&:save!)
  end

  private

  def new_entry(purpose, from_warehouse_id:, to_warehouse_id:)
    @account.mes_stock_entries.new(
      purpose: purpose, status: 'DRAFT', outsource_order_id: @order.id,
      production_order_id: @order.production_order_id, product_line: @order.product_line,
      from_warehouse_id: from_warehouse_id, to_warehouse_id: to_warehouse_id,
      owner_id: @actor&.id, remark: "委外加工单 #{@order.order_no} · #{@order.mes_supplier&.name}"
    )
  end

  def default_raw_warehouse_id
    @account.mes_warehouses.where(kind: 'RAW').order(:id).pick(:id)
  end

  def outsource_warehouse_id!
    @order.mes_warehouse_id.presence ||
      raise(Error, '这张加工单还没指定委外仓——料发出去要落在哪个仓，不指定就成了凭空消失')
  end

  # 还没发的标准用量。分批发料时只带剩下的那部分。
  def default_issue_rows
    @order.outsource_materials.filter_map do |material|
      left = material.std_qty.to_d - @order.issued_qty_for(material)
      next if left <= 0

      { material: material, qty: left }
    end
  end

  # 倒冲：按实收台数 × 每台标准用量。
  # 不按「已发多少扣多少」——发多了是加工厂手上的余料，该走退料单回来，不能算进消耗。
  def backflush_rows(received)
    @order.outsource_materials.filter_map do |material|
      per_unit = @order.qty.to_d.zero? ? 0 : material.std_qty.to_d / @order.qty.to_d
      consume = (per_unit * received).round(3)
      next if consume <= 0

      material_item_attrs(material: material, qty: consume).merge(warehouse_id: outsource_warehouse_id!)
    end
  end

  def material_item_attrs(row = nil, material: nil, qty: nil)
    material ||= row[:material]
    qty ||= row[:qty]
    { account_id: @account.id, item_type: 'MATERIAL', qty: qty, unit: material.unit,
      mes_material_id: material.mes_material_id, crm_product_id: material.crm_product_id,
      warehouse_id: material.from_warehouse_id }
  end

  def product_item_attrs(qty, warehouse_id)
    { account_id: @account.id, item_type: 'PRODUCT', qty: qty, unit: @order.unit,
      crm_product_id: @order.crm_product_id, warehouse_id: warehouse_id }
  end

  def find_material(id)
    @order.outsource_materials.find_by(id: id) || raise(Error, "用料行 ##{id} 不在这张加工单上")
  end

  def ensure_returnable!(material, qty)
    raise Error, '退料数量要大于 0' if qty <= 0

    left = @order.returnable_qty_for(material)
    return if qty <= left

    raise Error, "#{material.display_name} 最多还能退 #{left}（已发 − 已耗 − 已退）"
  end
end
