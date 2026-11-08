# 工作台首页卡片的真实数据（当前用户视角）。全员可用（不走 CRM 门禁）：
# 各卡片只统计本人相关数据，非销售人员 CRM 计数自然为 0。
class Api::V1::Accounts::Crm::HomeStatsController < Api::V1::Accounts::BaseController
  def index
    uid = current_user.id
    render json: { crm: crm_stats(uid), hr: attendance_week(uid, Time.zone.today.beginning_of_week),
                   leads: lead_stats(uid) }
  end

  private

  def crm_stats(uid)
    today = Time.zone.today
    cust = Current.account.crm_customers.where(account_owner_id: uid)
    {
      follow_up_due: cust.where('next_follow_up_at IS NOT NULL AND next_follow_up_at <= ?', today.end_of_day).count,
      new_today: cust.where(created_at: today.all_day).count,
      revisit_week: Current.account.crm_follow_up_notes
                           .where(owner_id: uid).where('created_at >= ?', week_start_time).count,
      overdue: cust.where('next_follow_up_at < ?', today.beginning_of_day).count
    }
  end

  # 新客开发：今天该处理几条。
  #
  # 不放在首页的后果实测（2026-11-08）：三个任务挖出 2746 家公司、399 家判「像买家」，
  # **建档 0、丢弃 0**——挖出来的东西没人动，整个板块的价值兑现不了。
  # 这个板块不像邮件会主动弹到人眼前，不摆在每天必看的地方就只能靠人想起来。
  #
  # 口径：自己负责的任务里，**能直接打的**那批——判像买家、分数够高、有联系人、
  # 不是同事已有客户。打不着或已经有人在跟的不该催人去看。
  READY_SCORE = 70

  def lead_stats(uid)
    campaign_ids = Current.account.crm_lead_campaigns.where(owner_id: uid).select(:id)
    leads = Current.account.crm_leads.where(crm_lead_campaign_id: campaign_ids)
    open_leads = leads.where(status: %w[FOUND UNLOCKED])
    {
      ready: open_leads.where("raw->>'screen' = 'yes'").where.not(person_name: nil)
                       .where(dup_customer_id: nil)
                       .where("COALESCE((raw->>'screen_score')::int, 0) >= ?", READY_SCORE)
                       .distinct.count(:company_name),
      claimed_week: leads.where(status: 'CLAIMED').where('crm_leads.updated_at >= ?', week_start_time).count
    }
  end

  def week_start_time = Time.zone.today.beginning_of_week.beginning_of_day

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
