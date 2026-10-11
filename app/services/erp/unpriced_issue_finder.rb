# 成本归集里按 0 计价的料。
#
# 材料成本 = Σ(领料 − 退料) × **最近一次采购单价**（Erp::CostRollupService）。某颗料从没
# 采购过、或采购单上没填价，就按 0 计——这是刻意的选择：宁可少算也不编数。
# 问题是「少算」不报错也不留痕，毛利表上只是悄悄偏高，财务看不出哪一笔不对。
# 这个清单把它摆出来：哪几颗料按 0 计了、领了多少、牵涉几张订单，照着补采购价就行。
#
# 口径与 CostRollupService 严格对齐（同样的采购单状态、同样认 mes_material_id/crm_product_id
# 两种挂法），否则这里报的「缺价」和那边实际按 0 算的会是两拨料。
class Erp::UnpricedIssueFinder
  ISSUE_PURPOSE = 'MATERIAL_ISSUE'.freeze
  COUNTED_PO_STATUSES = Erp::CostRollupService::COUNTED_PO_STATUSES

  def initialize(account)
    @account = account
  end

  # from/to 按销售订单下单日期圈范围（与毛利报表同一组筛选条件）。
  # => { count:, rows: [{ code:, name:, qty:, order_count: }] }（rows 按牵涉订单数倒序）
  def perform(from: nil, to: nil)
    rows = issue_rows(from, to)
    return { count: 0, rows: [] } if rows.empty?

    unpriced = rows.reject { |row| priced?(row) }
    grouped = group(unpriced)
    { count: grouped.size, rows: grouped }
  end

  private

  # 已过账的领料行（退料不算：退料本身也按同一个 0 价冲回，不构成新的缺价）。
  # 只看挂了销售订单的生产订单——成本归集本来就只处理这些。
  def issue_rows(from, to)
    scope = Mes::StockEntryItem
            .joins(stock_entry: :production_order)
            .where(account_id: @account.id)
            .where(mes_stock_entries: { purpose: ISSUE_PURPOSE, status: 'POSTED' })
            .where.not(mes_production_orders: { crm_sales_order_id: nil })
    scope = scope.where(mes_production_orders: { crm_sales_order_id: order_ids(from, to) }) if from.present? || to.present?
    plucked = scope.pluck(:mes_material_id, :crm_product_id, :qty, :received_qty,
                          'mes_production_orders.crm_sales_order_id')
    plucked.map do |material_id, product_id, qty, received, order_id|
      { material_id: material_id, product_id: product_id, order_id: order_id,
        qty: (received.presence || qty).to_d }
    end
  end

  def order_ids(from, to)
    scope = @account.crm_sales_orders
    scope = scope.where(order_date: from..) if from.present?
    scope = scope.where(order_date: ..to) if to.present?
    scope.select(:id)
  end

  def priced?(row)
    priced_material_ids.include?(row[:material_id]) || priced_product_ids.include?(row[:product_id])
  end

  def purchased_scope
    Mes::PurchaseItem.joins(:purchase_order)
                     .where(account_id: @account.id)
                     .where(mes_purchase_orders: { status: COUNTED_PO_STATUSES })
                     .where('mes_purchase_items.rate_micros > 0')
  end

  def priced_material_ids
    @priced_material_ids ||= purchased_scope.distinct.pluck(:mes_material_id).compact.to_set
  end

  def priced_product_ids
    @priced_product_ids ||= purchased_scope.distinct.pluck(:crm_product_id).compact.to_set
  end

  # 同一颗料可能既被领料行挂 mes_material_id、又被另一行挂 crm_product_id，
  # 按这两个 id 的组合分组（跟计价缓存的键一致），不按名字——名字会重。
  def group(rows)
    rows.group_by { |row| [row[:material_id], row[:product_id]] }
        .map { |(material_id, product_id), lines| summarize(material_id, product_id, lines) }
        .sort_by { |row| [-row[:order_count], row[:code].to_s] }
  end

  def summarize(material_id, product_id, lines)
    named = material_names[material_id] || product_names[product_id] || {}
    {
      code: named[:code], name: named[:name],
      qty: lines.sum { |line| line[:qty] }.to_f,
      order_count: lines.pluck(:order_id).uniq.size
    }
  end

  def material_names
    @material_names ||= @account.mes_materials.pluck(:id, :material_no, :name)
                                .to_h { |id, no, name| [id, { code: no, name: name }] }
  end

  def product_names
    @product_names ||= @account.crm_products.pluck(:id, :sku, :name)
                               .to_h { |id, sku, name| [id, { code: sku, name: name }] }
  end
end
