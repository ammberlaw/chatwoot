# 团队看板：按团队查看本月成交额/新成交客户数与各组员目标完成率。
# 对齐 Twenty team-dashboard front-component：下拉切团队，团队合计 + 组员逐行进度条。
class Api::V1::Accounts::Crm::TeamDashboardController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    # current_team_id 给前端做默认选中：管理员能看全部团队，按名称排序时
    # 「1688」这种数字队名永远排最前，每次打开都是它——默认先落到自己所属的队。
    render json: {
      month_label: month_label,
      teams: teams_payload,
      current_team_id: Current.account_user.crm_team_id
    }
  end

  private

  # 参考月：优先 year+month 参数（前端下拉筛选），非法或缺省回落当月。
  def ref_date
    @ref_date ||= begin
      year = params[:year].to_i
      month = params[:month].to_i
      year.positive? && month.between?(1, 12) ? Date.new(year, month, 1) : Time.zone.today
    end
  end

  def month_range
    ref_date.all_month
  end

  def month_label
    "#{ref_date.year}年#{ref_date.month}月"
  end

  # 本月实绩：成交额来自非取消订单(按 owner)，新客户数来自本月首次成交客户(按 account_owner)
  def actual_amount_by_owner
    @actual_amount_by_owner ||=
      Current.account.crm_sales_orders.dealt
             .where(order_date: month_range).group(:owner_id).sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))
  end

  def actual_count_by_owner
    @actual_count_by_owner ||=
      Current.account.crm_customers
             .where(first_deal_at: month_range.first.beginning_of_day..month_range.last.end_of_day)
             .group(:account_owner_id).count
  end

  def target_by_owner
    @target_by_owner ||= begin
      rows = Current.account.crm_sales_targets.for_month(ref_date)
                    .group(:owner_id)
                    .pluck(:owner_id, Arel.sql('SUM(target_amount_micros)'), Arel.sql('SUM(target_order_count)'))
      rows.to_h { |owner_id, amount, count| [owner_id, { amount: amount || 0, count: count || 0 }] }
    end
  end

  # 本年逐月的团队合计。顶部 KPI 卡要拿它算环比、画走势——只给当月的话，
  # 卡上那个数字没有参照系，看的人得自己翻上个月。
  def year_range
    ref_date.all_year
  end

  def monthly_amount_by_owner
    @monthly_amount_by_owner ||=
      Current.account.crm_sales_orders.dealt
             .where(order_date: year_range)
             .group(:owner_id, Arel.sql('EXTRACT(MONTH FROM order_date)::int'))
             .sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))
             .tap { |h| h.default = 0 }
  end

  def monthly_count_by_owner
    @monthly_count_by_owner ||=
      Current.account.crm_customers
             .where(first_deal_at: year_range.first.beginning_of_day..year_range.last.end_of_day)
             .group(:account_owner_id, Arel.sql('EXTRACT(MONTH FROM first_deal_at)::int'))
             .count
             .tap { |h| h.default = 0 }
  end

  def monthly_target_by_owner
    @monthly_target_by_owner ||=
      Current.account.crm_sales_targets
             .where(target_month: year_range)
             .pluck(:owner_id, Arel.sql('EXTRACT(MONTH FROM target_month)::int'),
                    :target_amount_micros, :target_order_count)
             .to_h { |owner_id, month, amount, count| [[owner_id, month], [amount || 0, count || 0]] }
             .tap { |h| h.default = [0, 0] }
  end

  # 「达标」＝成交额做到月目标的八成。没设目标的人不算进达标，也不算落后。
  ACHIEVED_RATIO = 0.8

  def achieved_count(member_ids, month)
    member_ids.count do |id|
      target = monthly_target_by_owner[[id, month]].first
      target.positive? && monthly_amount_by_owner[[id, month]] >= target * ACHIEVED_RATIO
    end
  end

  def month_row(member_ids, month)
    targets = member_ids.map { |id| monthly_target_by_owner[[id, month]] }
    {
      month: month,
      amount_micros: member_ids.sum { |id| monthly_amount_by_owner[[id, month]] },
      count: member_ids.sum { |id| monthly_count_by_owner[[id, month]] },
      target_amount_micros: targets.sum(&:first),
      target_count: targets.sum(&:last),
      achieved_members: achieved_count(member_ids, month)
    }
  end

  def monthly_rows(member_ids)
    (1..12).map { |month| month_row(member_ids, month) }
  end

  def teams_payload
    visible_teams.order(:name).includes(:members).map do |team|
      members = team.members.map { |user| member_row(user) }
                    .sort_by { |m| -m[:actual_amount_micros] }
      { id: team.id, name: team.name, members: members,
        monthly: monthly_rows(team.members.map(&:id)) }
    end
  end

  # 超级管理员/管理员看全部团队；部门主管与业务员仅看自己所属团队。
  def visible_teams
    return Current.account.crm_teams if Current.account_user.administrator? || Current.account_user.crm_deputy_admin?

    Current.account.crm_teams.where(id: Current.account_user.crm_team_id)
  end

  # 上月同口径，给组员表的「较上月」算完成率涨跌。
  # 1 月没有上月（逐月表只覆盖本年），返回 nil，前端那一列留空。
  def prev_month_number
    ref_date.month > 1 ? ref_date.month - 1 : nil
  end

  def prev_member_stats(user_id)
    month = prev_month_number
    return { amount: nil, target_amount: nil, count: nil, target_count: nil } if month.nil?

    target_amount, target_count = monthly_target_by_owner[[user_id, month]]
    {
      amount: monthly_amount_by_owner[[user_id, month]],
      target_amount: target_amount,
      count: monthly_count_by_owner[[user_id, month]],
      target_count: target_count
    }
  end

  def member_row(user)
    target = target_by_owner[user.id] || { amount: 0, count: 0 }
    prev = prev_member_stats(user.id)
    {
      id: user.id,
      name: user.name,
      actual_amount_micros: actual_amount_by_owner[user.id] || 0,
      actual_count: actual_count_by_owner[user.id] || 0,
      target_amount_micros: target[:amount],
      target_count: target[:count],
      prev_amount_micros: prev[:amount],
      prev_target_amount_micros: prev[:target_amount],
      prev_count: prev[:count],
      prev_target_count: prev[:target_count]
    }
  end

  def check_authorization
    authorize(Crm::Team)
  end
end
