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

  # 导出用数据（JSON）：汇总 + **每日明细**。前端用 SheetJS 写成两个 sheet 的 xlsx。
  #
  # 为什么不在后端直接生成文件：Ruby 侧没有 xlsx 写库，而 CSV 只有一张表，
  # 塞不下「汇总 + 每天打卡时间」两种不同列宽的内容（HR 原话：导出只有汇总那一页，
  # 每天的打卡时间啥的都没有）。前端 SheetJS 是现成依赖（MES/ERP 导出都在用）。
  # 权限与数据范围跟 summary/export 完全一致。
  def export_data
    return render_forbidden unless admin_like? || Current.account_user.crm_manager?

    range = summary_range
    users = summary_users
    records = Current.account.crm_attendance_records
                     .includes(:adjusted_by)
                     .where(user_id: users.map(&:id), work_date: range)
                     .order(:user_id, :work_date)
                     .group_by(&:user_id)
    render json: {
      range: { from: range.first, to: range.last },
      # 日期列头：工作日给日号、周末给「六/日」（照钉钉的月度汇总排版）
      dates: range.map { |d| { date: d, day: d.day, weekday: d.cwday, label: date_header(d) } },
      summary: users.map { |u| summary_row(u, status_counts(u.id, records[u.id] || [], range)) },
      matrix: users.map { |u| matrix_row(u, records[u.id] || [], range) }
    }
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

  # 快下班了才来打当天第一次卡 → 视为忘打上班卡后补打下班（上班留空走补卡）。
  #
  # 原先用「上下班时段中点」当分界，但上午请假、下午才来上班的人（14:00 到岗）会被
  # 误判成下班卡。改成「下班时间前 CLOCK_OUT_WINDOW_MINUTES 分钟起」：下午来上班的
  # 照样记上班，临下班才来打的才记下班。
  # 无法解析考勤组时间时保守回退：不判为下班（维持原「首打即上班」）。
  CLOCK_OUT_WINDOW_MINUTES = 60

  def past_workday_midpoint?(ctx)
    threshold = clock_out_window_start(ctx[:group])
    return false if threshold.nil?

    now = ctx[:now]
    (now.hour * 60 + now.min) >= threshold
  end

  def clock_out_window_start(group)
    i = parse_hm(group&.clock_in_time)
    o = parse_hm(group&.clock_out_time)
    return nil if i.nil? || o.nil? || o <= i

    # 上下班间隔太短（不足两倍窗口）时退回中点，避免阈值落到上班时间之前。
    o - i < CLOCK_OUT_WINDOW_MINUTES * 2 ? (i + o) / 2 : o - CLOCK_OUT_WINDOW_MINUTES
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

  # 旷工：已过去的工作日没有记录（按该成员所属组的工作日口径）。
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

  # 日期列头：周末只写「六 / 日」，工作日写日号——一个月 31 列，写全日期会挤成一团。
  WEEK_CHARS = %w[一 二 三 四 五 六 日].freeze

  def date_header(date)
    date.cwday >= 6 ? WEEK_CHARS[date.cwday - 1] : date.day.to_s
  end

  # 一人一行：左边统计列 + 整月每天一个格子（格子里是文字，不是打卡时间）。
  def matrix_row(user, records, range)
    group = group_for(user.id)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    by_date = records.index_by(&:work_date)
    stat = { late_count: 0, late_minutes: 0, early_count: 0, early_minutes: 0,
             miss_in: 0, miss_out: 0, field_days: 0, present: 0, expected: 0 }

    cells = range.map do |date|
      # 非工作日 / 还没到的日子都留空，不写「旷工」——钉钉也是空着
      next '' unless group.work_day?(date) && date <= today

      stat[:expected] += 1
      tally_cell(by_date[date], group, stat)
    end

    { user_id: user.id, name: user.name, group_name: group&.name,
      department: department_name(user), **stat, cells: cells }
  end

  # 单个格子的文字 + 顺带累加左侧统计。没有记录＝旷工。
  def tally_cell(rec, group, stat)
    return '旷工' if rec.nil? || rec.status == 'ABSENT'

    stat[:field_days] += 1 if rec.field
    stat[:miss_in] += 1 if rec.clock_in_at.nil? && %w[NORMAL LATE EARLY_LEAVE LATE_EARLY FIELD].include?(rec.status)
    stat[:miss_out] += 1 if rec.clock_out_at.nil? && %w[NORMAL LATE EARLY_LEAVE LATE_EARLY FIELD].include?(rec.status)
    if %w[LEAVE HALF_LEAVE].include?(rec.status)
      # 半天假算半天出勤，与汇总页的 present 口径一致
      stat[:present] += 0.5 if rec.status == 'HALF_LEAVE'
      return leave_cell_text(rec)
    end

    stat[:present] += 1
    parts = []
    late = late_minutes(rec, group)
    early = early_minutes(rec, group)
    if late.positive?
      stat[:late_count] += 1
      stat[:late_minutes] += late
      parts << "上班迟到#{late}分钟"
    end
    if early.positive?
      stat[:early_count] += 1
      stat[:early_minutes] += early
      parts << "下班早退#{early}分钟"
    end
    parts << '上班缺卡' if rec.clock_in_at.nil?
    parts << '下班缺卡' if rec.clock_out_at.nil?
    parts << '外勤' if rec.field
    parts.empty? ? '正常' : parts.join('，')
  end

  # 请假格子：有备注就直接写备注（审批联动带过来的本来就是「事假 10-06 09:00到18:00 8小时」
  # 这种完整说明，再加「请假」前缀反而啰嗦）；没备注才退回「请假 / 请假(半天)」。
  def leave_cell_text(rec)
    rec.note.presence || (rec.status == 'HALF_LEAVE' ? '请假(半天)' : '请假')
  end

  # 迟到/早退分钟数：拿打卡时间和考勤组的上下班点比，扣掉宽限。
  # 组里存的是 "09:00" 这种字符串，按当天日期拼成时刻再比。
  def late_minutes(rec, group)
    return 0 if rec.clock_in_at.nil? || group.nil?

    due = time_on(rec.work_date, group.clock_in_time)
    return 0 if due.nil?

    diff = ((rec.clock_in_at - due) / 60).floor - group.grace_minutes.to_i
    [diff, 0].max
  end

  def early_minutes(rec, group)
    return 0 if rec.clock_out_at.nil? || group.nil?

    due = time_on(rec.work_date, group.clock_out_time)
    return 0 if due.nil?

    [((due - rec.clock_out_at) / 60).floor, 0].max
  end

  def time_on(date, hhmm)
    return nil if hhmm.blank?

    Time.use_zone(Crm::AttendanceRecord::TZ) { Time.zone.parse("#{date} #{hhmm}") }
  rescue ArgumentError
    nil
  end

  def department_name(user)
    @department_names ||= Current.account.crm_employees.where.not(user_id: nil)
                                 .includes(:department).index_by(&:user_id)
                                 .transform_values { |e| e.department&.name }
    @department_names[user.id]
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
      clock_out_time: group.clock_out_time, break_start_time: group.break_start_time,
      break_end_time: group.break_end_time, grace_minutes: group.grace_minutes,
      holidays: group.holidays, extra_workdays: group.extra_workdays,
      geo_enabled: group.geo_enabled, ip_enabled: group.ip_enabled,
      office_lat: group.office_lat&.to_f, office_lng: group.office_lng&.to_f,
      geo_radius_m: group.geo_radius_m }
  end
end
# rubocop:enable Metrics/ClassLength
