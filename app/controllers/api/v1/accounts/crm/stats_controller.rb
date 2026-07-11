# 数据看板聚合：一次返回 KPI + 全年按月成交额 + 漏斗计数。
# scope=mine 时按当前用户过滤（个人数据看板），默认全公司。
class Api::V1::Accounts::Crm::StatsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    year = (params[:year] || Time.zone.today.year).to_i
    range = Time.zone.local(year, 1, 1)...Time.zone.local(year + 1, 1, 1)

    orders = Current.account.crm_sales_orders.dealt.where(order_date: range)
    orders = orders.owned_by(current_user.id) if mine?

    month_expr = Arel.sql("DATE_TRUNC('month', order_date)")
    monthly = orders.group(month_expr).sum(:order_amount_micros)

    this_month = Time.zone.today.beginning_of_month
    month_orders = orders.where(order_date: this_month..)

    opportunities = Current.account.crm_opportunities
    opportunities = opportunities.owned_by(current_user.id) if mine?

    customers = Current.account.crm_customers
    customers = customers.owned_by(current_user.id) if mine?

    render json: {
      month_amount_micros: month_orders.sum(:order_amount_micros),
      month_order_count: month_orders.count,
      month_deal_customers: month_orders.where.not(crm_customer_id: nil).distinct.count(:crm_customer_id),
      month_new_customers: customers.where(first_deal_at: this_month..).count,
      total_customers: customers.count,
      public_pool_customers: Current.account.crm_customers.in_public_pool.count,
      open_opportunities: opportunities.open_stages.count,
      funnel: opportunities.group(:sales_stage).count,
      monthly_amount_micros: (1..12).index_with { |m| monthly[Time.zone.local(year, m, 1)] || 0 },
      target: current_target
    }
  end

  private

  def mine?
    params[:scope] == 'mine'
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  # 本月目标（个人=自己的；公司=全员合计）
  def current_target
    scope = Current.account.crm_sales_targets.for_month(Time.zone.today)
    scope = scope.owned_by(current_user.id) if mine?
    { amount_micros: scope.sum(:target_amount_micros), new_customers: scope.sum(:target_order_count) }
  end
end
