# 存货 FIFO 核算：入库建批次层、出库按先进先出逐层扣、作废原样还回。
#
# 口径与金蝶一致（财务确认金蝶用先进先出），E9 平行跑账才对得上。
#
# **成品**：现货出库按 FIFO 结转，成本挂到销售订单（attribute_shipment!）。
# **原料**（2026-10-12 补）：采购收货按那一批的实际采购价建层，领料按先进先出逐层扣。
#   原来原料一律按「最近一次采购单价」计价——备货期价格一变，先备的那批货就按新价出账，
#   库存备得越早、波动越大，成本偏得越多。现在每批货自带它进货时的价。
#   领料消耗记录由 CostRollupService 直接拿去归集订单成本（见那边的 material_amount）。
#
# 挂载点是 Mes::StockEntry 过账/作废（库存唯一进出口），MES 侧只调用不持有金额（ERP_SPEC §13-1）。
class Erp::StockCostService
  class Error < StandardError; end

  PRODUCT = 'PRODUCT'.freeze
  MATERIAL = 'MATERIAL'.freeze
  IN_PURPOSES = %w[MATERIAL_RECEIPT MANUFACTURE].freeze
  OUT_PURPOSES = %w[SHIPMENT SCRAP].freeze
  # 原料侧：领料是出（扣层），退料是回（按当初领出去的价重新建层）。
  MATERIAL_ISSUE = 'MATERIAL_ISSUE'.freeze
  MATERIAL_RETURN = 'MATERIAL_RETURN'.freeze

  def initialize(account)
    @account = account
  end

  # 过账后调用：入库建层 / 出库耗层。返回本单成品成本合计（micros，出库为正数）。
  def sync_entry!(entry)
    case entry.purpose
    when MATERIAL_ISSUE then material_items(entry).sum { |item| consume!(entry, item) }
    when MATERIAL_RETURN then return_materials!(entry)
    else sync_stock_entry!(entry)
    end
  end

  # 作废：入库单撤层（已被出库消耗过的层不能撤——货都发出去了，撤层会让后续成本算错）；
  # 出库单按消耗记录原样还回各层。
  def reverse_entry!(entry)
    # 领料作废＝把扣掉的层原样还回；退料作废＝撤掉回库建的那些层。
    if IN_PURPOSES.include?(entry.purpose) || entry.purpose == MATERIAL_RETURN
      revert_layers!(entry)
    elsif OUT_PURPOSES.include?(entry.purpose) || entry.purpose == MATERIAL_ISSUE
      restore_consumptions!(entry)
    end
  end

  # 把一张现货出库单的 FIFO 成本挂到它的销售订单上（库存单轨道的成本来源）。
  #
  # ⚠️ 只对现货出库（kind=STOCK）做。定制单的成本已由 CostRollupService 按领料/外协归集，
  # 它的成品出库若再按 FIFO 挂一次，同一批货就被算两遍——与 CostRollupService 里
  # 「自产按领料、外协按采购，二选一互不重叠」是同一条原则。
  # 幂等：一张出库单一条成本行，重复调只更新金额。
  def attribute_shipment!(shipment, entry)
    return unless shipment.stock?
    return if shipment.crm_sales_order_id.blank?

    amount = @account.erp_stock_consumptions.where(mes_stock_entry_id: entry.id).sum(:base_amount_micros).to_i
    row = @account.erp_order_costs.find_by(source_type: 'Mes::Shipment', source_id: shipment.id)
    return row&.destroy! if amount <= 0

    write_shipment_cost(row, shipment, amount)
  end

  # 期初建账/手工补层：财务从金蝶导出的成品期初（数量+单价+入库日）。
  def open_layer!(crm_product_id:, warehouse_id:, qty:, unit_cost_micros:, received_at:, remark: nil)
    @account.erp_stock_layers.create!(
      crm_product_id: crm_product_id, warehouse_id: warehouse_id,
      qty_in: qty, qty_remaining: qty, unit_cost_micros: unit_cost_micros,
      received_at: received_at, source_type: 'Erp::OpeningInventory', remark: remark
    )
  end

  private

  def write_shipment_cost(row, shipment, amount)
    attrs = {
      crm_sales_order_id: shipment.crm_sales_order_id,
      cost_type: 'MATERIAL', amount_micros: amount,
      currency: 'CNY', exchange_rate: 1,
      remark: "由现货出库单 #{shipment.shipment_no} 按先进先出结转"
    }
    if row
      row.update!(attrs)
    else
      @account.erp_order_costs.create!(
        attrs.merge(source_type: 'Mes::Shipment', source_id: shipment.id, happened_at: Date.current)
      )
    end
  end

  # 成品原路径（成品收货/完工入库建层，出货/报废扣层）。
  def sync_stock_entry!(entry)
    # 入库建层要把**原料行一起建**：原料 FIFO 的整条链是「采购收货建层 → 领料逐层扣」，
    # 入库只建成品层的话原料一层都没有，领料时无层可扣，成本只能回落到「最近一次采购单价」
    # ——那正是 2026-10-12 这次改造要消灭的口径（备货期价格一变，先备的货按新价出账）。
    # 生产上实测：74 行原料入库建出 0 个批次层，改造做了一半。
    #
    # 出库（SHIPMENT/SCRAP）仍只认成品行：卖出去/报废的是成品，原料的消耗走领料那条路。
    return build_layers!(entry, layer_items(entry)) if IN_PURPOSES.include?(entry.purpose)

    items = product_items(entry)
    return 0 if items.empty?
    return items.sum { |item| consume!(entry, item) } if OUT_PURPOSES.include?(entry.purpose)

    0
  end

  # 入库建层的行：成品按商品档认，原料挂物料档或商品档都算（屏、主板这些建在商品档里）。
  def layer_items(entry)
    entry.stock_entry_items.select do |item|
      if item.item_type == PRODUCT
        item.crm_product_id.present?
      else
        item.mes_material_id.present? || item.crm_product_id.present?
      end
    end
  end

  def product_items(entry)
    entry.stock_entry_items.select { |item| item.item_type == PRODUCT && item.crm_product_id.present? }
  end

  def build_layers!(entry, items)
    items.each { |item| build_layer!(entry, item) }
    0
  end

  # 原料行：挂物料档或商品档都算（屏、主板这些建在商品档里，只认物料档会漏掉大多数行）。
  def material_items(entry)
    entry.stock_entry_items.select do |item|
      item.item_type != PRODUCT && (item.mes_material_id.present? || item.crm_product_id.present?)
    end
  end

  # 退料回库：按**当初从这张生产订单领出去的均价**重新建层。
  # 不按最近采购价——退回来的就是当初领走的那批货，用新价会凭空制造成本差。
  # 取不到当初的领料记录（上核算之前领的）就落到最近采购价，取不到就 0。
  def return_materials!(entry)
    material_items(entry).each do |item|
      qty = item.effective_qty
      next if qty <= 0

      @account.erp_stock_layers.create!(
        crm_product_id: item.crm_product_id, mes_material_id: item.mes_material_id,
        warehouse_id: item.warehouse_id || entry.to_warehouse_id,
        qty_in: qty, qty_remaining: qty,
        unit_cost_micros: Erp::MaterialReturnCost.new(@account).for(entry, item),
        received_at: entry.posted_at || Time.current,
        source_type: 'Mes::StockEntry', source_id: entry.id,
        remark: "生产退料 #{entry.entry_no}"
      )
    end
    0
  end

  # ── 入库：建一层 ──────────────────────────────────────────────
  def build_layer!(entry, item)
    qty = item.effective_qty
    return if qty <= 0

    @account.erp_stock_layers.create!(
      crm_product_id: item.crm_product_id,
      mes_material_id: item.mes_material_id,
      warehouse_id: item.warehouse_id || entry.to_warehouse_id,
      qty_in: qty, qty_remaining: qty,
      unit_cost_micros: Erp::StockLayerCost.new(@account).for(entry, item, qty),
      received_at: entry.posted_at || Time.current,
      source_type: 'Mes::StockEntry', source_id: entry.id,
      remark: layer_remark(entry)
    )
  end

  def layer_remark(entry)
    entry.purpose == 'MANUFACTURE' ? "完工入库 #{entry.entry_no}" : "采购收货 #{entry.entry_no}"
  end

  # ── 出库：FIFO 逐层扣 ────────────────────────────────────────
  def consume!(entry, item)
    qty_left = item.effective_qty
    return 0 if qty_left <= 0

    total = 0
    layers = @account.erp_stock_layers
                     .for_item(item.crm_product_id, item.warehouse_id || entry.from_warehouse_id,
                               item.mes_material_id)
                     .open_layers.lock # 行锁：并发出库不能同时吃掉同一层
    layers.each do |layer|
      break if qty_left <= 0

      take = [layer.qty_remaining, qty_left].min
      total += record_consumption!(entry, item, layer, take)
      qty_left -= take
    end
    # 层不够＝有货却没成本来源（期初没导、或入库那会儿还没上核算）。
    # 不拦出库（货是实实在在发出去的），差额留 0 成本，存货页能看出缺口。
    total
  end

  def record_consumption!(entry, item, layer, qty)
    amount = (qty * layer.unit_cost_micros).round
    layer.update!(qty_remaining: layer.qty_remaining - qty)
    @account.erp_stock_consumptions.create!(
      stock_layer_id: layer.id, mes_stock_entry_id: entry.id,
      crm_product_id: item.crm_product_id, mes_material_id: item.mes_material_id,
      qty: qty, base_amount_micros: amount
    )
    amount
  end

  # ── 作废回滚 ────────────────────────────────────────────────
  def revert_layers!(entry)
    layers = @account.erp_stock_layers.where(source_type: 'Mes::StockEntry', source_id: entry.id)
    layers.each do |layer|
      raise Error, "入库单 #{entry.entry_no} 的货已有部分出库，不能作废（请先作废相关出库单）" if layer.qty_remaining < layer.qty_in

      layer.destroy!
    end
  end

  def restore_consumptions!(entry)
    @account.erp_stock_consumptions.where(mes_stock_entry_id: entry.id).includes(:stock_layer).find_each do |row|
      layer = row.stock_layer
      layer.update!(qty_remaining: layer.qty_remaining + row.qty)
      row.destroy!
    end
  end
end
