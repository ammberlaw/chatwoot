# 考勤：打卡与查询全员可用（含无 CRM 角色成员）；汇总按数据范围（超管/管理员全员、部门负责人本部门）；修正仅超管/管理员。
# 单控制器聚合打卡/月历/汇总/导出/修正/网络，方法多但内聚，故豁免 ClassLength。
# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Crm::AttendancesController < Api::V1::Accounts::Crm::BaseController
  skip_before_action :ensure_crm_access

  OVERVIEW_KEYS = %i[expected present late early_leave absent leave field].freeze

  # 月度考勤（默认自己；超管/管理员/负责人可带 user_id 看可见范围内成员）。
  # setting 返回该成员所属考勤组的规则（各组上下班时间/工作日可不同）。
  def index
    user_id = viewable_user_id
    records = Current.account.crm_attendance_records
                     .where(user_id: user_id, work_date: month_range)
                     .includes(:adjusted_by)
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

    render json: record_json(punch!(group: group, field: field, lat: lat, lng: lng, ip: ip))
  rescue TooSoon => e
    render json: { error: e.message }, status: :unprocessable_entity
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
    agg = aggregate(users, range)
    render json: {
      payload: agg[:rows], overview: agg[:overview],
      range: { start: range.first, end: range.last },
      setting: group_json(group_for(current_user.id)),
      not_clocked_today: not_clocked_today(users),
      groups: summary_groups
    }
  end

  # 汇总聚合：一次查库、逐人计数、累加概览。
  def aggregate(users, range)
    records = Current.account.crm_attendance_records
                     .where(user_id: users.map(&:id), work_date: range)
                     .group_by(&:user_id)
    overview = Hash.new(0)
    rows = users.map do |u|
      row = summary_row(u, status_counts(u.id, records[u.id] || [], range))
      OVERVIEW_KEYS.each { |k| overview[k] += row[k] }
      row
    end
    { rows: rows, overview: overview }
  end

  # 月度考勤导出（CSV，供 HR 对接工资）：与汇总同权限、同数据范围。
  def export
    return render_forbidden unless admin_like? || Current.account_user.crm_manager?

    range = summary_range
    users = summary_users
    records = Current.account.crm_attendance_records
                     .where(user_id: users.map(&:id), work_date: range)
                     .group_by(&:user_id)
    rows = users.map { |u| summary_row(u, status_counts(u.id, records[u.id] || [], range)) }
    csv = Crm::AttendanceCsvService.new(rows: rows, range: range).generate
    send_data csv, type: 'text/csv; charset=utf-8', filename: "考勤_#{range.first}_#{range.last}.csv"
  end

  # 单人某月考勤统计（只读参考，供绩效/工资页展示）：本人可看自己，管理员/负责人可看他人。
  def user_summary
    uid = params[:user_id].to_i
    return render_forbidden unless admin_like? || Current.account_user.crm_manager? || uid == current_user.id

    target = Current.account.users.find_by(id: uid)
    return render json: { error: '成员不存在' }, status: :unprocessable_entity if target.nil?

    render json: month_stats(target)
  end

  # HR 修正：给某人某天直接定状态（可补建记录），留审计与修正人；source=hr（审批联动不覆盖）。
  def adjust
    return render_forbidden unless admin_like?
    return render json: { error: '无效的状态' }, status: :unprocessable_entity unless Crm::AttendanceRecord::STATUSES.include?(params[:status])

    target = Current.account.users.find_by(id: params[:user_id])
    work_date = parse_date(params[:work_date])
    return render json: { error: '成员或日期无效' }, status: :unprocessable_entity if target.nil? || work_date.nil?

    render json: record_json(upsert_adjustment(target.id, work_date))
  end

  private

  def parse_date(str)
    Date.iso8601(str.to_s)
  rescue ArgumentError
    nil
  end

  def month_stats(target)
    range = month_range
    records = Current.account.crm_attendance_records.where(user_id: target.id, work_date: range).to_a
    row = summary_row(target, status_counts(target.id, records, range))
    rate = row[:expected].positive? ? (row[:present].to_f / row[:expected]).round(3) : nil
    row.merge(rate: rate)
  end

  # HR 修正与员工当天打卡可能并发命中同一 (user_id, work_date) 唯一键；
  # 与 punch! 同法：撞键后重取（此时记录已由打卡建好）再覆盖为 HR 修正值。
  def upsert_adjustment(user_id, work_date)
    attempts = 0
    begin
      rec = Current.account.crm_attendance_records.find_or_initialize_by(user_id: user_id, work_date: work_date)
      rec.assign_attributes(status: params[:status], note: params[:note].presence,
                            adjusted_by_id: current_user.id, source: 'hr')
      rec.save!
      rec
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts += 1) > 1

      retry
    end
  end

  # 今日应到却未打上班卡的成员（只看今天，与所选粒度无关；供负责人早会点名）。
  def not_clocked_today(users)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    clocked = Current.account.crm_attendance_records
                     .where(user_id: users.map(&:id), work_date: today)
                     .where.not(clock_in_at: nil).pluck(:user_id).to_set
    users.select { |u| group_for(u.id).work_day?(today) && clocked.exclude?(u.id) }
         .map { |u| { user_id: u.id, name: u.name } }
  end

  # 一次打卡落库：首次记上班、之后记下班；外勤(field)持久化并置 FIELD（当天保持外勤）。
  # find_or_initialize + save! 遇同天并发/连点会撞唯一键，rescue 后重取（此时已存在→按下班处理）。
  # 上班后 MIN_WORK_MINUTES 分钟内再打卡会被当成下班，用异常挡掉并提示。
  TooSoon = Class.new(StandardError)

  def punch!(group:, field:, lat:, lng:, ip:)
    now = Time.current.in_time_zone(Crm::AttendanceRecord::TZ)
    ctx = { now: now, field: field, lat: lat, lng: lng, ip: ip, group: group }
    attempts = 0
    begin
      rec = Current.account.crm_attendance_records
                   .find_or_initialize_by(user_id: current_user.id, work_date: now.to_date)
      if too_soon_to_clock_out?(rec, now)
        raise TooSoon, "刚打过上班卡（#{rec.clock_in_at.in_time_zone(Crm::AttendanceRecord::TZ).strftime('%H:%M')}），" \
                       "#{MIN_WORK_MINUTES} 分钟内不记下班卡，避免误触"
      end

      apply_punch(rec, ctx)
      rec.save!
      rec
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts += 1) > 1

      retry
    end
  end

  # 上班卡刚打完手滑再点一下，第二下会被当成下班卡（实测两次相差 0.6 秒，当天直接记早退）。
  # 上班后这段时间内不接受下班打卡——正常人不会上班一分钟就下班，误触却很常见。
  MIN_WORK_MINUTES = 10

  def too_soon_to_clock_out?(rec, now)
    rec.clock_in_at.present? && rec.clock_out_at.nil? &&
      now - rec.clock_in_at < MIN_WORK_MINUTES.minutes
  end

  def apply_punch(rec, ctx)
    if rec.clock_in_at.nil? && !ctx[:field] && past_workday_midpoint?(ctx)
      # 忘打上班卡、当天较晚(已过工作时段中点)才来打 → 记为下班；上班留空(显示缺上班卡，走补卡)，
      # 不再把这一下误记成「上班」导致下不了班。
      rec.assign_attributes(clock_out_at: ctx[:now], clock_out_ip: ctx[:ip],
                            clock_out_lat: ctx[:lat].presence, clock_out_lng: ctx[:lng].presence)
    elsif rec.clock_in_at.nil?
      rec.assign_attributes(clock_in_at: ctx[:now], clock_in_ip: ctx[:ip],
                            clock_in_lat: ctx[:lat].presence, clock_in_lng: ctx[:lng].presence)
    else
      rec.assign_attributes(clock_out_at: ctx[:now], clock_out_ip: ctx[:ip],
                            clock_out_lat: ctx[:lat].presence, clock_out_lng: ctx[:lng].presence)
    end
    rec.field = true if ctx[:field]
    if rec.field?
      rec.status = 'FIELD' unless rec.adjusted_by_id
    else
      rec.recompute_status!(ctx[:group])
    end
  end

  # 当天首次打卡但已过「上班~下班时段中点」→ 视为忘打上班卡后补打下班（上班留空走补卡）。
  # 无法解析考勤组时间时保守回退：不判为下班（维持原「首打即上班」）。
  def past_workday_midpoint?(ctx)
    mid = workday_midpoint_minutes(ctx[:group])
    return false if mid.nil?

    now = ctx[:now]
    (now.hour * 60 + now.min) >= mid
  end

  def workday_midpoint_minutes(group)
    i = parse_hm(group&.clock_in_time)
    o = parse_hm(group&.clock_out_time)
    return nil if i.nil? || o.nil? || o <= i

    (i + o) / 2
  end

  def parse_hm(str)
    return nil unless str.to_s =~ /\A(\d{1,2}):(\d{2})\z/

    (Regexp.last_match(1).to_i * 60) + Regexp.last_match(2).to_i
  end

  # 账号全部考勤组一次性载入，避免汇总时按成员逐个查库（N+1）。
  def all_groups
    @all_groups ||= Current.account.crm_attendance_groups.to_a
  end

  # 按成员解析所属考勤组（未分组→默认组），全程内存解析、一次请求内缓存。
  def group_for(user_id)
    @groups_cache ||= {}
    @groups_cache[user_id] ||= all_groups.find { |g| g.user_ids.include?(user_id) } || default_group
  end

  def default_group
    @default_group ||= all_groups.find(&:is_default?) || Crm::AttendanceGroup.default_for(Current.account)
  end

  # 打卡地点校验失败文案：按该组开启的方式提示。
  def location_error(group)
    ways = []
    ways << '在打卡范围内(GPS)' if group.geo_enabled?
    ways << '连接公司网络(WiFi)' if group.ip_enabled?
    "打卡失败：需#{ways.join(' 或 ')}。请确认后重试"
  end

  # 人事按考勤管理职能纳入 admin_like：可查全员考勤、改考勤、设打卡网络/地点。
  def admin_like?
    au = Current.account_user
    au.administrator? || au.crm_deputy_admin? || au.crm_hr?
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
    scope = scope.where(id: subordinate_user_ids + [current_user.id]) unless admin_like?
    filter_by_group(scope)
  end

  # 可选按考勤组筛选：普通组=组内成员；默认组=未分入任何显式组的成员。
  def filter_by_group(scope)
    return scope if params[:group_id].blank?

    group = all_groups.find { |g| g.id == params[:group_id].to_i }
    return scope unless group
    return scope.where(id: group.user_ids) unless group.is_default?

    assigned = all_groups.reject(&:is_default?).flat_map(&:user_ids).uniq
    scope.where.not(id: assigned)
  end

  # 汇总页考勤组下拉数据（默认组排最后）。
  def summary_groups
    all_groups.sort_by { |g| [g.is_default? ? 1 : 0, g.name] }
              .map { |g| { id: g.id, name: g.name, is_default: g.is_default } }
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
    rescue ArgumentError, TypeError
      Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date.beginning_of_month
    end
    month.all_month
  end

  # 汇总区间：按 period（day/week/month，默认 month）+ date（默认今天）算日期范围。
  def summary_range
    base = begin
      Date.parse(params[:date])
    rescue ArgumentError, TypeError
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
    half = c['HALF_LEAVE']
    present = c['NORMAL'] + c['LATE'] + c['EARLY_LEAVE'] + c['LATE_EARLY'] + c['FIELD'] + (half * 0.5)
    { user_id: user.id, name: user.name, expected: c.values.sum, present: present,
      late: c['LATE'] + c['LATE_EARLY'], early_leave: c['EARLY_LEAVE'] + c['LATE_EARLY'],
      absent: c['ABSENT'], leave: c['LEAVE'] + (half * 0.5), field: c['FIELD'] }
  end

  def record_json(rec)
    tz = Crm::AttendanceRecord::TZ
    { id: rec.id, user_id: rec.user_id, work_date: rec.work_date,
      clock_in_at: rec.clock_in_at&.in_time_zone(tz)&.strftime('%H:%M'),
      clock_out_at: rec.clock_out_at&.in_time_zone(tz)&.strftime('%H:%M'),
      status: rec.status, note: rec.note, source: rec.source, adjusted_by_name: rec.adjusted_by&.name }
  end

  def group_json(group)
    { name: group.name, work_days: group.work_days, clock_in_time: group.clock_in_time,
      clock_out_time: group.clock_out_time, grace_minutes: group.grace_minutes,
      holidays: group.holidays, extra_workdays: group.extra_workdays,
      geo_enabled: group.geo_enabled, ip_enabled: group.ip_enabled,
      office_lat: group.office_lat&.to_f, office_lng: group.office_lng&.to_f,
      geo_radius_m: group.geo_radius_m }
  end
end
# rubocop:enable Metrics/ClassLength
