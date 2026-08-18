# 工作台首页卡片的真实数据（当前用户视角）。全员可用（不走 CRM 门禁）：
# 各卡片只统计本人相关数据，非销售人员 CRM 计数自然为 0。
class Api::V1::Accounts::Crm::HomeStatsController < Api::V1::Accounts::BaseController
  def index
    uid = current_user.id
    today = Time.zone.today
    week_start = today.beginning_of_week

    cust = Current.account.crm_customers.where(account_owner_id: uid)

    render json: {
      crm: {
        follow_up_due: cust.where('next_follow_up_at IS NOT NULL AND next_follow_up_at <= ?', today.end_of_day).count,
        new_today: cust.where(created_at: today.all_day).count,
        revisit_week: Current.account.crm_follow_up_notes
                             .where(owner_id: uid).where('created_at >= ?', week_start.beginning_of_day).count,
        overdue: cust.where('next_follow_up_at < ?', today.beginning_of_day).count
      },
      hr: attendance_week(uid, week_start)
    }
  end

  private

  # 本周(周一起)每天是否出勤；前 5 天(工作日)全出勤 = 全勤。
  def attendance_week(uid, week_start)
    recs = Crm::AttendanceRecord.where(account_id: Current.account.id, user_id: uid,
                                       work_date: week_start..(week_start + 6)).index_by(&:work_date)
    days = (0..6).map do |i|
      r = recs[week_start + i]
      { present: r.present? && !%w[ABSENT LEAVE].include?(r&.status), workday: i < 5 }
    end
    { days: days, all_present: days.first(5).all? { |x| x[:present] } }
  end
end
