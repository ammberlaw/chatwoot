# 毛利：订单收入 - 归集成本，实时算不落库（ERP_SPEC §4.2）。
#
# 收入口径：优先取应收台账金额（财务确认过的），没建台账就退回销售订单金额。
# 成本口径：erp_order_costs 归集行的本位币合计。
# 只在 ERP 内可见——销售端接口一律不得输出这些数（§13-2）。
class Erp::MarginService
  def initialize(account)
    @account = account
  end

  # 订单维度毛利表。
  def by_order(from: nil, to: nil, limit: 200)
    orders = order_scope(from, to).limit(limit).to_a
    receivables = @account.erp_receivables.where(crm_sales_order_id: orders.map(&:id)).index_by(&:crm_sales_order_id)
    costs = cost_totals(orders.map(&:id))
    orders.map { |order| row_for(order, receivables[order.id], costs[order.id].to_i) }
  end

  # 汇总维度（业务员 / 客户），拿订单行再聚合。
  def summary_by(dimension, from: nil, to: nil)
    rows = by_order(from: from, to: to, limit: 1000)
    grouped = rows.group_by { |row| dimension == 'customer' ? row[:customer_name] : row[:owner_name] }
    grouped.map { |name, group| aggregate(name, group) }.sort_by { |row| -row[:revenue_micros] }
  end

  private

  def order_scope(from, to)
    scope = @account.crm_sales_orders.includes(:crm_customer, :owner).order(order_date: :desc)
    scope = scope.where(order_date: from..) if from.present?
    scope = scope.where(order_date: ..to) if to.present?
    scope
  end

  def cost_totals(order_ids)
    @account.erp_order_costs.where(crm_sales_order_id: order_ids)
            .group(:crm_sales_order_id)
            .sum(Arel.sql('ROUND(amount_micros * exchange_rate)'))
  end

  def row_for(order, receivable, cost_micros)
    revenue = revenue_of(order, receivable)
    margin = revenue - cost_micros
    order_identity(order).merge(
      revenue_micros: revenue, cost_micros: cost_micros, margin_micros: margin,
      margin_rate: rate_of(margin, revenue), receivable_no: receivable&.receivable_no
    )
  end

  def order_identity(order)
    {
      order_id: order.id, order_no: order.order_no, order_name: order.name,
      order_date: order.order_date&.to_date,
      customer_name: order.crm_customer&.name,
      owner_name: order.owner&.crm_name.presence || order.owner&.name
    }
  end

  def rate_of(margin, revenue)
    revenue.positive? ? (margin * 100.0 / revenue).round(2) : nil
  end

  # 收入折本位币：台账/订单都可能是外币，一律按其汇率折算。
  def revenue_of(order, receivable)
    if receivable
      (receivable.total_amount_micros * receivable.exchange_rate).round
    else
      (order.order_amount_micros.to_i * (order.exchange_rate.presence || 1)).round
    end
  end

  def aggregate(name, group)
    revenue = group.sum { |row| row[:revenue_micros] }
    cost = group.sum { |row| row[:cost_micros] }
    {
      name: name.presence || '未指定', order_count: group.size,
      revenue_micros: revenue, cost_micros: cost, margin_micros: revenue - cost,
      margin_rate: rate_of(revenue - cost, revenue)
    }
  end
end
