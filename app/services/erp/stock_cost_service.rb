# 成品存货 FIFO 核算：入库建批次层、出库按先进先出逐层扣、作废原样还回。
#
# 口径与金蝶一致（财务确认金蝶用先进先出），E9 平行跑账才对得上。
# 只管**成品**：原材料耗用已由 CostRollupService 按领料归到定制订单，再核算一遍就是重复计算。
#
# 挂载点是 Mes::StockEntry 过账/作废（库存唯一进出口），MES 侧只调用不持有金额（ERP_SPEC §13-1）。
class Erp::StockCostService
  class Error < StandardError; end

  PRODUCT = 'PRODUCT'.freeze
  IN_PURPOSES = %w[MATERIAL_RECEIPT MANUFACTURE].freeze
  OUT_PURPOSES = %w[SHIPMENT SCRAP].freeze

  def initialize(account)
    @account = account
  end

  # 过账后调用：入库建层 / 出库耗层。返回本单成品成本合计（micros，出库为正数）。
  def sync_entry!(entry)
    items = entry.stock_entry_items.select { |item| item.item_type == PRODUCT && item.crm_product_id.present? }
    return 0 if items.empty?

    if IN_PURPOSES.include?(entry.purpose)
      items.each { |item| build_layer!(entry, item) }
      0
    elsif OUT_PURPOSES.include?(entry.purpose)
      items.sum { |item| consume!(entry, item) }
    else
      0
    end
  end

  # 作废：入库单撤层（已被出库消耗过的层不能撤——货都发出去了，撤层会让后续成本算错）；
  # 出库单按消耗记录原样还回各层。
  def reverse_entry!(entry)
    if IN_PURPOSES.include?(entry.purpose)
      revert_layers!(entry)
    elsif OUT_PURPOSES.include?(entry.purpose)
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

  # ── 入库：建一层 ──────────────────────────────────────────────
  def build_layer!(entry, item)
    qty = item.effective_qty
    return if qty <= 0

    @account.erp_stock_layers.create!(
      crm_product_id: item.crm_product_id,
      warehouse_id: item.warehouse_id || entry.to_warehouse_id,
      qty_in: qty, qty_remaining: qty,
      unit_cost_micros: unit_cost_for(entry, item, qty),
      received_at: entry.posted_at || Time.current,
      source_type: 'Mes::StockEntry', source_id: entry.id,
      remark: layer_remark(entry)
    )
  end

  # 单位成本来源二选一，与 CostRollupService 的「自产按领料、外协按采购」同一套口径：
  #   外购成品收货 → 采购行金额 ÷ 数量
  #   自产完工入库 → 该生产订单归集成本 ÷ 完工数量
  # 取不到价的按 0 建层——宁可少算也不编数，成本页/存货页看得见，财务可手工补。
  def unit_cost_for(entry, item, qty)
    micros = case entry.purpose
             when 'MATERIAL_RECEIPT' then purchase_unit_cost(entry, item)
             when 'MANUFACTURE' then manufacture_unit_cost(entry, qty)
             else 0
             end
    [micros.to_i, 0].max
  end

  def purchase_unit_cost(entry, item)
    line = purchase_line_for(entry, item)
    return 0 if line.nil?

    (line.amount_micros / line.qty.to_d).round
  end

  def purchase_line_for(entry, item)
    lines = entry.purchase_order&.purchase_items || []
    line = lines.find { |pi| pi.item_type == PRODUCT && pi.crm_product_id == item.crm_product_id }
    return nil if line.nil?

    priced_line(line)
  end

  def priced_line(line)
    return nil if line.amount_micros.blank?
    return nil if line.qty.to_d <= 0

    line
  end

  def manufacture_unit_cost(entry, qty)
    order = entry.production_order
    return 0 if order.blank? || qty <= 0

    total = Erp::CostRollupService.new(@account).production_cost_micros(order)
    return 0 if total.to_i <= 0

    (total / qty).round
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
                     .for_item(item.crm_product_id, item.warehouse_id || entry.from_warehouse_id)
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
      crm_product_id: item.crm_product_id, qty: qty, base_amount_micros: amount
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
