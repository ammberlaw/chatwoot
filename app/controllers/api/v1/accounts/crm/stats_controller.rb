# 数据看板聚合：一次返回三个标签页所需的全部数据。
#   ① 业绩概览  —— period_stats（月×12/季×4/年，前端切换无需重取）+ target
#   ② 趋势与转化 —— trends（月度成交额、商机按阶段金额）+ source_breakdown（客户来源）
#   ③ 团队与客户 —— totals（累计 KPI）+ team（团队/业务员对比、回复时长）
# scope=mine 时按当前用户过滤（个人数据看板），默认全公司。
class Api::V1::Accounts::Crm::StatsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  STAGE_ORDER = %w[NEEDS_CONFIRMED SAMPLING PENDING_PAYMENT WON LOST].freeze

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
    params[:scope] == 'mine' || !company_scope_allowed?
  end

  # 公司级看板对所有 CRM 成员开放（用户 2026-10-29 定：「外贸销售部数据看板也开放给所有
  # crm 成员」）。原先只给管理员/副管/主管，业务员直接访问 URL 也会被强制成个人口径。
  #
  # ⚠️ 开放的是**业绩口径**：成交额、商机、客户来源、团队与业务员对比（含按人名列出的
  # 月度成交额、赢单客户数、录入完整度、回复时长、发信量）。
  # 成本 / 供应商 / 毛利不在这个接口里，生态硬约束不受影响。
  def company_scope_allowed?
    true
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

  # 发出去的信（供「业务员发信排行」）：收件箱里那些不算，草稿/定时/发送失败的也不算，
  # 只认真正发成功的那一封。取 email_date（这封信自己的时间）而不是 created_at，
  # 补收回来的历史邮件才会落在真实发信月份。
  def sent_emails
    scope = Current.account.crm_emails.in_folder('SENT').where(send_status: 'SENT')
    mine? ? scope.owned_by(current_user.id) : scope
  end

  # ═══ Tab① 业绩统计：月/季/年三套桶，成交客户为 distinct 不可跨桶相加，故各自聚合 ═══
  def period_stats
    { monthly: buckets_by('month', 12), quarterly: buckets_by('quarter', 4), yearly: yearly_bucket }
  end

  def buckets_by(unit, count)
    series = bucket_series(unit)
    (1..count).map do |i|
      month = unit == 'month' ? i : ((i - 1) * 3) + 1
      key = Time.zone.local(@year, month, 1)
      { period: i }.merge(series.transform_values { |h| h[key] || 0 })
    end
  end

  # 一个周期单位下的各项按桶聚合：键是桶的起始时间，值是该桶的数。
  def bucket_series(unit)
    trunc = Arel.sql("DATE_TRUNC('#{unit}', order_date)")
    order_series(trunc).merge(
      new_customers: by_bucket(customers.where(first_deal_at: year_range), unit, 'first_deal_at')
    )
  end

  def order_series(trunc)
    {
      amount_micros: year_orders.group(trunc).sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)),
      order_count: year_orders.group(trunc).count,
      deal_customers: year_orders.where.not(crm_customer_id: nil).group(trunc).distinct.count(:crm_customer_id)
    }
  end

  def by_bucket(scope, unit, column)
    scope.group(Arel.sql("DATE_TRUNC('#{unit}', #{column})")).count
  end

  def yearly_bucket
    {
      period: @year,
      amount_micros: year_orders.sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)),
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
      opportunity_count_by_stage: STAGE_ORDER.index_with { |s| stage_count[s] || 0 },
      opportunity_currency: dominant_opportunity_currency
    }
  end

  # 商机阶段分布图的显示币种：取金额占比最大的币种（同司通常单一币种；混币时以主币种示意）。
  def dominant_opportunity_currency
    opportunities.where.not(amount_micros: nil)
                 .group(:currency).sum(:amount_micros)
                 .max_by { |_, micros| micros.to_i }&.first.presence || 'CNY'
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
      total_order_amount_micros: all_orders.sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)),
      dealt_customers_total: customers.where.not(first_deal_at: nil).count,
      public_pool_customers: Current.account.crm_customers.in_public_pool.count,
      avg_reply_latency_hours: emails.average(:reply_latency_hours)&.to_f&.round(1)
    }.merge(private_pool_totals)
  end

  # 私海 = 没被退回公海的那批（scope=mine 时就是「我手上的客户」）。
  # 资料完善度只对私海算：公海客户没人维护，算进平均分只会把分数拉低。
  def private_pool_totals
    scope = customers.where(is_in_public_pool: false)
    {
      private_customers: scope.count,
      private_completeness: scope.average(:info_completeness_score)&.to_f&.round(1)
    }
  end

  def team_stats
    {
      by_team_amount: all_orders.joins(:crm_team).group('crm_teams.name').sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)),
      by_owner_monthly: owner_monthly_amount,
      by_owner_won_customers: customers.where(customer_status: 'WON').joins(:account_owner).group('users.name').count,
      by_owner_completeness: completeness_by_owner,
      by_owner_reply_latency: emails.joins(:owner).group('users.name').average(:reply_latency_hours)
                                    .transform_values { |v| v.to_f.round(1) },
      by_owner_sent_emails: owner_monthly_sent_emails,
      top_customers: top_customers
    }
  end

  # 客户成交排行（Top Customers）：当年按「客户 × 月」预聚合金额与单数，前端按所选期间
  # 即时汇总，和业务员排行同一套做法，不另外请求。查询在模型里（和金额 SQL 放一起）。
  def top_customers
    rows = Crm::SalesOrder.monthly_customer_ranking(year_orders)
    mask_customers? ? rows.map { |row| mask_customer(row) } : rows
  end

  # 业务员看全公司看板时，别人客户的**公司名**要打码。
  #
  # 看板 2026-10-29 对全员开放，但成交排行上摆着同事客户的公司全名，等于把客户名单
  # 摊开给所有人——撞单、挖客的口子。金额和排名照给（业绩透明是开放看板的目的），
  # 名字换成「客户 01」这种序号，id 也不下发，前端点不进去。
  #
  # 自己的客户不打码：看自己的单不需要遮。
  # 在后端打码而不是前端：前端遮只是不画出来，接口里还在，F12 一看就有。
  def mask_customers?
    return false if params[:scope] == 'mine'

    au = Current.account_user
    !(au.administrator? || au.crm_deputy_admin? || au.crm_manager? || au.crm_finance?)
  end

  # 只遮**公司名和 id**（名字是客户名单、id 能点进详情）。
  # 国家留着——地区排行就是按它算的，抹掉会让别人的客户全挤进「未填写国家」，
  # 整张「成交客户地区排行」只剩一行（2026-10-29 上线当天就被发现）。
  # 国家本身不是客户名单，看板给的地区分布正是开放它的目的。
  def mask_customer(row)
    return row if my_customer_ids.include?(row[:id])

    row.merge(id: nil, name: nil, masked: true)
  end

  def my_customer_ids
    @my_customer_ids ||= Current.account.crm_customers.owned_by(current_user.id).pluck(:id).to_set
  end

  # 业务员发信排行：和成交排行同一套做法，按「业务员 × 月份」预聚合，
  # 前端按所选周期即时汇总。归属按邮件的 owner（这封信是谁发的）。
  def owner_monthly_sent_emails
    with_zero_owners(monthly_by_owner(sent_emails.where(email_date: year_range).joins(:owner), 'email_date'))
  end

  # 业务员成交排行：当年按「业务员 × 月份」预聚合（下单日期口径），
  # 返回 { 姓名 => [1..12月金额] }，前端按所选期间（月/季/年）即时汇总，无需重取。
  def owner_monthly_amount
    trunc = Arel.sql("DATE_TRUNC('month', order_date)")
    raw = year_orders.joins(:owner).group('users.name', trunc)
                     .sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))
    with_zero_owners(spread_by_month(raw))
  end

  # 把勾了「计入业绩排行」但这个月没出单的人也补成全 0 的一行。
  # group 只聚合得出「有单的人」，没开张的直接从榜上消失——而那几位恰恰最该被看见。
  # 谁上榜由人事在成员管理里勾（account_users.in_sales_rank），不靠系统猜：
  # 规则再细也有例外——副管兼跑业务要算、挂 manager 的生产主管不算、空号不算。
  def with_zero_owners(rows)
    Current.account.account_users.active_members.where(in_sales_rank: true)
           .includes(:user).each do |au|
      name = au.user&.name
      rows[name] ||= Array.new(12, 0) if name.present?
    end
    rows
  end

  # { 姓名 => [1..12月的数] }：按月份计数，缺的月份补 0。
  def monthly_by_owner(scope, column)
    spread_by_month(scope.group('users.name', Arel.sql("DATE_TRUNC('month', #{column})")).count)
  end

  def spread_by_month(raw)
    raw.each_with_object(Hash.new { |h, k| h[k] = Array.new(12, 0) }) do |((name, month), value), acc|
      acc[name][month.month - 1] = value.to_i
    end
  end

  def completeness_by_owner
    customers.joins(:account_owner).group('users.name').average(:info_completeness_score)
             .transform_values { |v| v.to_f.round }
  end

  def check_authorization
    authorize(Crm::Customer)
  end

  # 目标（个人=自己的；公司=全员合计）。原来只给「当前月」一个数，前端切到季度/年度、
  # 或者翻到别的月份，分母都还是本月的目标——对不上。改成和 period_stats 一样给全套桶，
  # 前端按所选周期取。进度的分子直接用 period_stats 里同一个周期的成交额。
  def current_target
    scope = Current.account.crm_sales_targets.where(target_month: year_range)
    scope = scope.owned_by(current_user.id) if mine?
    by_month = scope.group(Arel.sql("DATE_TRUNC('month', target_month)")).sum(:target_amount_micros)
    monthly = (1..12).map { |m| by_month[Time.zone.local(@year, m, 1)] || 0 }
    { monthly: monthly, quarterly: monthly.each_slice(3).map(&:sum), yearly: monthly.sum }
  end
end
