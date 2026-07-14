# 数据看板聚合：一次返回三个标签页所需的全部数据。
#   ① 业绩概览  —— period_stats（月×12/季×4/年，前端切换无需重取）+ target
#   ② 趋势与转化 —— trends（月度成交额、商机按阶段金额）+ source_breakdown（客户来源）
#   ③ 团队与客户 —— totals（累计 KPI）+ team（团队/业务员对比、回复时长）
# scope=mine 时按当前用户过滤（个人数据看板），默认全公司。
class Api::V1::Accounts::Crm::StatsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  STAGE_ORDER = %w[NEEDS_CONFIRMED SAMPLING WON LOST].freeze

  def show
    @year = (params[:year] || Time.zone.today.year).to_i

    render json: {
      year: @year,
      period_stats: period_stats,
      target: current_target,
      trends: trends,
      source_breakdown: source_breakdown,
      totals: totals,
      team: team_stats
    }
  end

  private

  def mine?
    params[:scope] == 'mine'
  end

  def year_range
    Time.zone.local(@year, 1, 1)...Time.zone.local(@year + 1, 1, 1)
  end

  # ── 各对象基础作用域（year_orders 限定当年；all_orders 累计）──
  def year_orders
    scope = Current.account.crm_sales_orders.dealt.where(order_date: year_range)
    mine? ? scope.owned_by(current_user.id) : scope
  end

  def all_orders
    scope = Current.account.crm_sales_orders.dealt
    mine? ? scope.owned_by(current_user.id) : scope
  end

  def opportunities
    scope = Current.account.crm_opportunities
    mine? ? scope.owned_by(current_user.id) : scope
  end

  def customers
    scope = Current.account.crm_customers
    mine? ? scope.owned_by(current_user.id) : scope
  end

  def emails
    scope = Current.account.crm_emails.where.not(reply_latency_hours: nil)
    mine? ? scope.owned_by(current_user.id) : scope
  end

  # ═══ Tab① 业绩统计：月/季/年三套桶，成交客户为 distinct 不可跨桶相加，故各自聚合 ═══
  def period_stats
    { monthly: buckets_by('month', 12), quarterly: buckets_by('quarter', 4), yearly: yearly_bucket }
  end

  def buckets_by(unit, count)
    trunc = Arel.sql("DATE_TRUNC('#{unit}', order_date)")
    amount = year_orders.group(trunc).sum(:order_amount_micros)
    counts = year_orders.group(trunc).count
    distinct = year_orders.where.not(crm_customer_id: nil).group(trunc).distinct.count(:crm_customer_id)
    new_trunc = Arel.sql("DATE_TRUNC('#{unit}', first_deal_at)")
    new_cust = customers.where(first_deal_at: year_range).group(new_trunc).count

    (1..count).map do |i|
      month = unit == 'month' ? i : ((i - 1) * 3) + 1
      key = Time.zone.local(@year, month, 1)
      {
        period: i,
        amount_micros: amount[key] || 0,
        order_count: counts[key] || 0,
        deal_customers: distinct[key] || 0,
        new_customers: new_cust[key] || 0
      }
    end
  end

  def yearly_bucket
    {
      period: @year,
      amount_micros: year_orders.sum(:order_amount_micros),
      order_count: year_orders.count,
      deal_customers: year_orders.where.not(crm_customer_id: nil).distinct.count(:crm_customer_id),
      new_customers: customers.where(first_deal_at: year_range).count
    }
  end

  # ═══ Tab② 趋势与转化 ═══
  def trends
    monthly = buckets_by('month', 12).map { |b| b[:amount_micros] }
    stage_amount = opportunities.group(:sales_stage).sum(:amount_micros)
    stage_count = opportunities.group(:sales_stage).count
    {
      monthly_amount_micros: monthly,
      opportunity_amount_by_stage: STAGE_ORDER.index_with { |s| stage_amount[s] || 0 },
      opportunity_count_by_stage: STAGE_ORDER.index_with { |s| stage_count[s] || 0 }
    }
  end

  # 客户来源占比：按建档时间（当年）统计各来源客户数
  def source_breakdown
    customers.where(created_at: year_range).where.not(source_channel: nil).group(:source_channel).count
  end

  # ═══ Tab③ 团队与客户 累计 KPI ═══
  def totals
    {
      total_customers: customers.count,
      won_customers: customers.where(customer_status: 'WON').count,
      open_opportunities: opportunities.open_stages.count,
      total_order_amount_micros: all_orders.sum(:order_amount_micros),
      dealt_customers_total: customers.where.not(first_deal_at: nil).count,
      public_pool_customers: Current.account.crm_customers.in_public_pool.count,
      avg_reply_latency_hours: emails.average(:reply_latency_hours)&.to_f&.round(1)
    }
  end

  def team_stats
    {
      by_team_amount: all_orders.joins(:crm_team).group('crm_teams.name').sum(:order_amount_micros),
      by_owner_amount: all_orders.joins(:owner).group('users.name').sum(:order_amount_micros),
      by_owner_won_customers: customers.where(customer_status: 'WON').joins(:account_owner).group('users.name').count,
      by_owner_completeness: completeness_by_owner,
      by_owner_reply_latency: emails.joins(:owner).group('users.name').average(:reply_latency_hours)
                                    .transform_values { |v| v.to_f.round(1) }
    }
  end

  def completeness_by_owner
    customers.joins(:account_owner).group('users.name').average(:info_completeness_score)
             .transform_values { |v| v.to_f.round }
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  # 本月目标（个人=自己的；公司=全员合计）+ 本月已成交额（进度分子）
  def current_target
    scope = Current.account.crm_sales_targets.for_month(Time.zone.today)
    scope = scope.owned_by(current_user.id) if mine?
    {
      amount_micros: scope.sum(:target_amount_micros),
      new_customers: scope.sum(:target_order_count),
      month_amount_micros: this_month_amount
    }
  end

  def this_month_amount
    all_orders.where(order_date: Time.zone.today.beginning_of_month..).sum(:order_amount_micros)
  end
end
