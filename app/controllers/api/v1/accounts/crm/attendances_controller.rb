# 考勤：打卡与查询全员可用（含无 CRM 角色成员）；汇总按数据范围（超管/管理员全员、部门负责人本部门）；修正仅超管/管理员。
class Api::V1::Accounts::Crm::AttendancesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access

  # 月度考勤（默认自己；超管/管理员/负责人可带 user_id 看可见范围内成员）
  def index
    user_id = viewable_user_id
    records = Current.account.crm_attendance_records
                     .where(user_id: user_id, work_date: month_range)
                     .order(:work_date)
    render json: {
      payload: records.map { |r| record_json(r) },
      setting: setting_json
    }
  end

  # 上班/下班打卡：第一次记上班，之后记下班（重复打卡取更晚时间，加班晚走再点一次即可）。
  def clock
    now = Time.current.in_time_zone(Crm::AttendanceRecord::TZ)
    rec = Current.account.crm_attendance_records
                 .find_or_initialize_by(user_id: current_user.id, work_date: now.to_date)
    if rec.clock_in_at.nil?
      rec.clock_in_at = now
    else
      rec.clock_out_at = now
    end
    rec.recompute_status!(setting)
    rec.save!
    render json: record_json(rec)
  end

  # 月度汇总：每人出勤/迟到/早退/缺卡/请假计数。
  def summary
    return render_forbidden unless admin_like? || Current.account_user.crm_manager?

    users = summary_users
    records = Current.account.crm_attendance_records
                     .where(user_id: users.map(&:id), work_date: month_range)
                     .group_by(&:user_id)
    rows = users.map { |u| summary_row(u, records[u.id] || []) }
    render json: { payload: rows, setting: setting_json }
  end

  # HR 修正：给某人某天直接定状态（可补建记录），留审计与修正人。
  def adjust
    return render_forbidden unless admin_like?
    return render json: { error: '无效的状态' }, status: :unprocessable_entity unless Crm::AttendanceRecord::STATUSES.include?(params[:status])

    rec = Current.account.crm_attendance_records
                 .find_or_initialize_by(user_id: params[:user_id], work_date: Date.parse(params[:work_date]))
    rec.assign_attributes(status: params[:status], note: params[:note].presence, adjusted_by_id: current_user.id)
    rec.save!
    render json: record_json(rec)
  end

  private

  def setting
    @setting ||= Crm::AttendanceSetting.for_account(Current.account)
  end

  def admin_like?
    Current.account_user.administrator? || Current.account_user.crm_deputy_admin?
  end

  def render_forbidden
    render json: { error: '无权限执行该操作' }, status: :forbidden
  end

  # 看谁的考勤：默认自己；带 user_id 时需在可见范围内（超管/管理员全员，负责人=下属）。
  def viewable_user_id
    target = params[:user_id].presence&.to_i
    return current_user.id if target.nil? || target == current_user.id
    return target if admin_like?
    return target if Current.account_user.crm_manager? && subordinate_user_ids.include?(target)

    current_user.id
  end

  def summary_users
    scope = Current.account.users.order(:name)
    return scope if admin_like?

    scope.where(id: subordinate_user_ids + [current_user.id])
  end

  def subordinate_user_ids
    @subordinate_user_ids ||= begin
      led = Current.account.org_departments.where(leader_id: current_user.id).pluck(:id)
      if led.empty?
        []
      else
        dept_ids = Org::Department.subtree_ids(Current.account, led)
        Current.account.org_memberships.where(department_id: dept_ids).pluck(:user_id).uniq - [current_user.id]
      end
    end
  end

  def month_range
    month = begin
      Date.parse("#{params[:month]}-01")
    rescue StandardError
      Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date.beginning_of_month
    end
    month.all_month
  end

  # 缺卡：已过去的工作日没有记录。
  def status_counts(records)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    by_date = records.index_by(&:work_date)
    counts = Hash.new(0)
    month_range.each do |date|
      next unless setting.work_day?(date) && date <= today

      counts[by_date[date]&.status || 'ABSENT'] += 1
    end
    counts
  end

  def summary_row(user, records)
    c = status_counts(records)
    present = c['NORMAL'] + c['LATE'] + c['EARLY_LEAVE'] + c['LATE_EARLY']
    { user_id: user.id, name: user.name, present: present,
      late: c['LATE'] + c['LATE_EARLY'], early_leave: c['EARLY_LEAVE'] + c['LATE_EARLY'],
      absent: c['ABSENT'], leave: c['LEAVE'] }
  end

  def record_json(rec)
    tz = Crm::AttendanceRecord::TZ
    { id: rec.id, user_id: rec.user_id, work_date: rec.work_date,
      clock_in_at: rec.clock_in_at&.in_time_zone(tz)&.strftime('%H:%M'),
      clock_out_at: rec.clock_out_at&.in_time_zone(tz)&.strftime('%H:%M'),
      status: rec.status, note: rec.note, adjusted_by_name: rec.adjusted_by&.name }
  end

  def setting_json
    { work_days: setting.work_days, clock_in_time: setting.clock_in_time,
      clock_out_time: setting.clock_out_time, grace_minutes: setting.grace_minutes,
      holidays: setting.holidays }
  end
end
