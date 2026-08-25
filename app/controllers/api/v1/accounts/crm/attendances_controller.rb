# 考勤：打卡与查询全员可用（含无 CRM 角色成员）；汇总按数据范围（超管/管理员全员、部门负责人本部门）；修正仅超管/管理员。
class Api::V1::Accounts::Crm::AttendancesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access

  # 月度考勤（默认自己；超管/管理员/负责人可带 user_id 看可见范围内成员）。
  # setting 返回该成员所属考勤组的规则（各组上下班时间/工作日可不同）。
  def index
    user_id = viewable_user_id
    records = Current.account.crm_attendance_records
                     .where(user_id: user_id, work_date: month_range)
                     .order(:work_date)
    render json: {
      payload: records.map { |r| record_json(r) },
      setting: group_json(group_for(user_id))
    }
  end

  # 上班/下班打卡：第一次记上班，之后记下班（重复打卡取更晚时间，加班晚走再点一次即可）。
  # 外勤打卡（field=true）：出差/客户现场，跳过地点校验并标记为外勤（计出勤、不判迟到）。
  def clock
    group = group_for(current_user.id)
    field = ActiveModel::Type::Boolean.new.cast(params[:field])
    lat = params[:lat]
    lng = params[:lng]
    ip = request.remote_ip
    if !field && !group.location_ok?(lat: lat, lng: lng, ip: ip)
      return render json: { error: location_error(group) }, status: :unprocessable_entity
    end

    now = Time.current.in_time_zone(Crm::AttendanceRecord::TZ)
    rec = Current.account.crm_attendance_records
                 .find_or_initialize_by(user_id: current_user.id, work_date: now.to_date)
    if rec.clock_in_at.nil?
      rec.clock_in_at = now
      rec.assign_attributes(clock_in_ip: ip, clock_in_lat: lat.presence, clock_in_lng: lng.presence)
    else
      rec.clock_out_at = now
      rec.assign_attributes(clock_out_ip: ip, clock_out_lat: lat.presence, clock_out_lng: lng.presence)
    end
    if field
      rec.status = 'FIELD' unless rec.adjusted_by_id
    else
      rec.recompute_status!(group)
    end
    rec.save!
    render json: record_json(rec)
  end

  # 返回当前请求的公网 IP，供管理员「把当前网络设为打卡网络」一键抓取。
  def my_network
    render json: { ip: request.remote_ip }
  end

  # 考勤汇总：按 period（day/week/month）+ date 聚合每人计数，并返回今日/本区间概览（供仪表盘）。
  def summary
    return render_forbidden unless admin_like? || Current.account_user.crm_manager?

    range = summary_range
    users = summary_users
    records = Current.account.crm_attendance_records
                     .where(user_id: users.map(&:id), work_date: range)
                     .group_by(&:user_id)
    overview = Hash.new(0)
    rows = users.map do |u|
      row = summary_row(u, status_counts(u.id, records[u.id] || [], range))
      %i[expected present late early_leave absent leave field].each { |k| overview[k] += row[k] }
      row
    end
    render json: {
      payload: rows, overview: overview,
      range: { start: range.first, end: range.last },
      setting: group_json(group_for(current_user.id))
    }
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

  # 按成员解析所属考勤组（未分组→默认组），一次请求内缓存。
  def group_for(user_id)
    @groups_cache ||= {}
    @groups_cache[user_id] ||= Crm::AttendanceGroup.for_user(Current.account, user_id)
  end

  # 打卡地点校验失败文案：按该组开启的方式提示。
  def location_error(group)
    ways = []
    ways << '在打卡范围内(GPS)' if group.geo_enabled?
    ways << '连接公司网络(WiFi)' if group.ip_enabled?
    "打卡失败：需#{ways.join(' 或 ')}。请确认后重试"
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

  # 汇总区间：按 period（day/week/month，默认 month）+ date（默认今天）算日期范围。
  def summary_range
    base = begin
      Date.parse(params[:date])
    rescue StandardError
      Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    end
    case params[:period]
    when 'day' then base..base
    when 'week' then base.beginning_of_week..base.end_of_week
    else base.beginning_of_month..base.end_of_month
    end
  end

  # 缺卡：已过去的工作日没有记录（按该成员所属组的工作日口径）。
  def status_counts(user_id, records, range)
    group = group_for(user_id)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    by_date = records.index_by(&:work_date)
    counts = Hash.new(0)
    range.each do |date|
      next unless group.work_day?(date) && date <= today

      counts[by_date[date]&.status || 'ABSENT'] += 1
    end
    counts
  end

  # 出勤=正常/迟到/早退/外勤都算到岗；应到(expected)=区间内所有该到的工作日格子。
  def summary_row(user, c)
    present = c['NORMAL'] + c['LATE'] + c['EARLY_LEAVE'] + c['LATE_EARLY'] + c['FIELD']
    { user_id: user.id, name: user.name, expected: c.values.sum, present: present,
      late: c['LATE'] + c['LATE_EARLY'], early_leave: c['EARLY_LEAVE'] + c['LATE_EARLY'],
      absent: c['ABSENT'], leave: c['LEAVE'], field: c['FIELD'] }
  end

  def record_json(rec)
    tz = Crm::AttendanceRecord::TZ
    { id: rec.id, user_id: rec.user_id, work_date: rec.work_date,
      clock_in_at: rec.clock_in_at&.in_time_zone(tz)&.strftime('%H:%M'),
      clock_out_at: rec.clock_out_at&.in_time_zone(tz)&.strftime('%H:%M'),
      status: rec.status, note: rec.note, adjusted_by_name: rec.adjusted_by&.name }
  end

  def group_json(group)
    { name: group.name, work_days: group.work_days, clock_in_time: group.clock_in_time,
      clock_out_time: group.clock_out_time, grace_minutes: group.grace_minutes,
      holidays: group.holidays,
      geo_enabled: group.geo_enabled, ip_enabled: group.ip_enabled,
      office_lat: group.office_lat&.to_f, office_lng: group.office_lng&.to_f,
      geo_radius_m: group.geo_radius_m }
  end
end
