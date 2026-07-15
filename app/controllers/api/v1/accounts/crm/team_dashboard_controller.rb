# 团队看板：按团队查看本月成交额/新成交客户数与各组员目标完成率。
# 对齐 Twenty team-dashboard front-component：下拉切团队，团队合计 + 组员逐行进度条。
class Api::V1::Accounts::Crm::TeamDashboardController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    render json: { month_label: month_label, teams: teams_payload }
  end

  private

  def month_range
    today = Time.zone.today
    today.beginning_of_month..today.end_of_month
  end

  def month_label
    today = Time.zone.today
    "#{today.year}年#{today.month}月"
  end

  # 本月实绩：成交额来自非取消订单(按 owner)，新客户数来自本月首次成交客户(按 account_owner)
  def actual_amount_by_owner
    @actual_amount_by_owner ||=
      Current.account.crm_sales_orders.dealt
             .where(order_date: month_range).group(:owner_id).sum(:order_amount_micros)
  end

  def actual_count_by_owner
    @actual_count_by_owner ||=
      Current.account.crm_customers
             .where(first_deal_at: month_range.first.beginning_of_day..month_range.last.end_of_day)
             .group(:account_owner_id).count
  end

  def target_by_owner
    @target_by_owner ||= begin
      rows = Current.account.crm_sales_targets.for_month(Time.zone.today)
                    .group(:owner_id)
                    .pluck(:owner_id, Arel.sql('SUM(target_amount_micros)'), Arel.sql('SUM(target_order_count)'))
      rows.to_h { |owner_id, amount, count| [owner_id, { amount: amount || 0, count: count || 0 }] }
    end
  end

  def teams_payload
    visible_teams.order(:name).includes(:members).map do |team|
      members = team.members.map { |user| member_row(user) }
                    .sort_by { |m| -m[:actual_amount_micros] }
      { id: team.id, name: team.name, members: members }
    end
  end

  # 管理员/主管看全部团队；普通业务仅看自己所属团队。
  def visible_teams
    if Current.account_user.administrator? || Current.account_user.crm_deputy_admin? || Current.account_user.crm_manager?
      return Current.account.crm_teams
    end

    Current.account.crm_teams.where(id: Current.account_user.crm_team_id)
  end

  def member_row(user)
    target = target_by_owner[user.id] || { amount: 0, count: 0 }
    {
      id: user.id,
      name: user.name,
      actual_amount_micros: actual_amount_by_owner[user.id] || 0,
      actual_count: actual_count_by_owner[user.id] || 0,
      target_amount_micros: target[:amount],
      target_count: target[:count]
    }
  end

  def check_authorization
    authorize(Crm::Team)
  end
end
