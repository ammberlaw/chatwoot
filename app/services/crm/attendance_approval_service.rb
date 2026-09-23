# 考勤审批联动：带考勤联动标记的审批单（请假/补卡）整单通过时自动写入考勤。
# - leave：取表单日期字段的最早/最晚值为区间，区间内每个工作日标「请假」；
# - reclock：取表单第一个日期字段的值，该天补为「正常」。
# 写入 source=approval（留审计），HR 手工修正(source=hr)优先、审批不覆盖；已实打卡的当天不改成请假。
# 写入在审批事务内进行，任何校验失败抛 WriteError → 回滚整单（fail loud，绝不半写）。
class Crm::AttendanceApprovalService
  class WriteError < StandardError; end

  MAX_LEAVE_SPAN_DAYS = 62

  # 承载日期的字段类型：date（纯日期）与 datetime（日期+时间下拉，值形如 2026-09-23T09:00）。
  # datetime 也要算进来——请假单改用带时间的字段后，若这里只认 date，
  # 审批通过将一条考勤都写不出来（静默失效，比报错更难查）。
  DATE_FIELD_TYPES = %w[date datetime].freeze

  # 模板里日期字段在 form_data 中的取值（按字段定义顺序；仅解析成功的）。
  def self.form_dates(template, form_data)
    date_field_values(template, form_data).filter_map { |v| parse_date(v) }
  end

  # 日期字段的原始非空取值（用于区分「未填」与「填了但格式错」）。
  def self.date_field_values(template, form_data)
    keys = Array(template.form_fields).select { |f| DATE_FIELD_TYPES.include?(f['type']) }.pluck('key')
    keys.map { |k| form_data[k] }.reject { |v| v.to_s.strip.empty? }
  end

  # 取时间部分（datetime 字段才有），形如 "09:00"；纯日期返回 nil。
  def self.form_times(template, form_data)
    date_field_values(template, form_data).filter_map do |v|
      t = v.to_s.split('T')[1]
      t.presence&.slice(0, 5)
    end
  end

  def self.parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # 表单里选择/文本字段值命中这些即视为半天假（模板没有时间字段时的兜底口径）。
  HALF_DAY_VALUES = %w[上午 下午 半天 上午半天 下午半天 半天假].freeze
  # 承载「时段」的字段类型。
  HALF_DAY_FIELD_TYPES = %w[select text].freeze

  # 单日请假是否算半天。口径：优先按时长——请假时段与本人考勤组工作时段的交集
  # ≤ 工作时长的一半即半天；时间没填全（纯日期模板 / 只填了一头）时回退到旧口径：
  # 选择/文本字段填了「上午/下午/半天」。
  #
  # 提交时算 leave_days（半天=0.5，条件路由要用）和通过时写考勤（HALF_LEAVE）
  # 必须是同一个判定，否则迟早出现「按 0.5 天走的审批却标了整天假」。
  def self.half_day?(account, applicant_id, template, form_data)
    by_duration = half_day_by_duration(account, applicant_id, template, form_data)
    return by_duration unless by_duration.nil?

    half_day_by_keyword(template, form_data)
  end

  # 按时长判定；判不了（时间不全 / 考勤组工作时长非正）返回 nil，交给关键字兜底。
  #
  # 两条规则，顺序有讲究：
  # 1) 只占了午休切出来的一段（上午 or 下午）→ 半天，不看长短。
  #    午休 12:00-13:30 让上午(3h)和下午(4.5h)不等长，单看「有没有过半」会把
  #    「下午请假」判成整天假——这是错的，所以先按「段」认。
  # 2) 跨了午休的（比如 11:00-15:00）→ 按扣掉午休的有效工作时长，不超过半个工作日算半天。
  def self.half_day_by_duration(account, applicant_id, template, form_data)
    times = form_times(template, form_data || {})
    return nil if times.size < 2

    group = Crm::AttendanceGroup.for_user(account, applicant_id)
    full = group.daily_work_minutes
    return nil unless full.positive?

    from, to = times.minmax.map { |t| Crm::AttendanceGroup.minutes(t) }
    return true if within_one_session?(group, from, to)

    group.working_minutes_between(from, to) * 2 <= full
  end

  # 请假是否只占了午休切出来的一段（上午 or 下午）。
  # 没配午休的组整天只有一段，认「段」等于无条件放行，所以直接判否、交给时长规则。
  def self.within_one_session?(group, from, to)
    sessions = group.work_sessions
    return false if sessions.size < 2

    sessions.count { |s_from, s_to| [to, s_to].min > [from, s_from].max } <= 1
  end

  def self.half_day_by_keyword(template, form_data)
    data = form_data || {}
    Array(template.form_fields).any? do |f|
      HALF_DAY_FIELD_TYPES.include?(f['type']) && HALF_DAY_VALUES.include?(data[f['key']].to_s.strip)
    end
  end

  # 请假/出差区间重叠校验：同一个人同一天不该有两张假单。返回错误文案或 nil。
  #
  # 不拦会怎样：考勤表是「一人一天一条」，后批准的单把先批准的记录覆盖并改认到自己名下，
  # 先批的那张单从此销不了假（系统认为它没写过考勤），统计上也会重复计入假期时长。
  #
  # 销假单本身与原单区间必然重叠，必须放行（revokes_request_id 有值的即是）。
  def self.overlap_violation(account, applicant_id, template, form_data, exclude_request_id: nil)
    return nil unless %w[leave trip].include?(template.attendance_kind)

    dates = form_dates(template, form_data)
    return nil if dates.empty?

    range = dates.min..dates.max
    conflict = overlapping_requests(account, applicant_id, exclude_request_id).find do |r|
      other = form_dates(r.template, r.form_data)
      other.any? && (other.min..other.max).overlaps?(range)
    end
    return nil if conflict.nil?

    "与已有的「#{conflict.title}」日期重叠（#{conflict.status == 'pending' ? '审批中' : '已通过'}），请先撤回或调整日期"
  end

  def self.overlapping_requests(account, applicant_id, exclude_request_id)
    scope = account.oa_approval_requests
                   .joins(:template)
                   .where(oa_approval_templates: { attendance_kind: %w[leave trip] },
                          applicant_id: applicant_id, status: %w[pending approved],
                          revokes_request_id: nil)
    scope = scope.where.not(id: exclude_request_id) if exclude_request_id
    scope.includes(:template)
  end

  # 补卡规则校验（按申请人所属考勤组）：返回错误文案或 nil。
  # 时限：只能补 window 天内的卡（0=不限）；上限：当月（按补卡日期归月）已提交/已通过的补卡单数（0=不允许补卡）。
  def self.reclock_violation(account, applicant_id, date, exclude_request_id: nil)
    group = Crm::AttendanceGroup.for_user(account, applicant_id)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    return '补卡日期不能是未来日期' if date > today
    return '该考勤组不允许补卡' if group.reclock_limit.zero?
    return "只能申请 #{group.reclock_window_days} 天内的补卡" if group.reclock_window_days.positive? && date < today - group.reclock_window_days

    used = reclock_used_in_month(account, applicant_id, date, exclude_request_id: exclude_request_id)
    return "当月补卡次数已达上限（#{group.reclock_limit} 次）" if used >= group.reclock_limit

    nil
  end

  # 当月已用补卡次数：审批中/已通过的补卡单，按其补卡日期归月统计。
  # exclude_request_id：改单复查时排除本单自身，避免把正在改的这单重复计入(off-by-one)。
  def self.reclock_used_in_month(account, applicant_id, date, exclude_request_id: nil)
    scope = account.oa_approval_requests
                   .joins(:template)
                   .where(oa_approval_templates: { attendance_kind: 'reclock' },
                          applicant_id: applicant_id, status: %w[pending approved])
    scope = scope.where.not(id: exclude_request_id) if exclude_request_id
    scope.count do |r|
      d = form_dates(r.template, r.form_data).first
      d && d.beginning_of_month == date.beginning_of_month
    end
  end

  def initialize(request:, actor:)
    @request = request
    @actor = actor
  end

  def perform
    case @request.template.attendance_kind
    when 'leave' then apply_leave
    when 'reclock' then apply_reclock
    when 'trip' then apply_trip
    end
  end

  private

  # 请假：单日 + 时长不超过半个工作日 → 半天假(HALF_LEAVE)；否则区间内每个工作日整天请假。
  def apply_leave
    range = resolve_range('请假单')
    if range.first == range.last && half_day?
      mark(range.first, 'HALF_LEAVE') if group.work_day?(range.first)
    else
      range.each { |date| mark(date, 'LEAVE') if group.work_day?(date) }
    end
  end

  # 出差：区间内每个工作日标外勤（FIELD，计出勤、不判迟到）。
  def apply_trip
    resolve_range('出差单').each { |date| mark(date, 'FIELD', field: true) if group.work_day?(date) }
  end

  # 解析日期区间（校验非空/格式/跨度），失败抛 WriteError。
  def resolve_range(label)
    filled = self.class.date_field_values(@request.template, @request.form_data)
    dates = filled.filter_map { |v| self.class.parse_date(v) }
    raise WriteError, "#{label}缺少有效日期，无法写入考勤" if dates.empty?
    raise WriteError, "#{label}日期格式有误，无法写入考勤" if dates.size != filled.size

    range = dates.min..dates.max
    raise WriteError, "#{label}区间超过 #{MAX_LEAVE_SPAN_DAYS} 天，请拆单提交" if (range.last - range.first).to_i > MAX_LEAVE_SPAN_DAYS

    range
  end

  def half_day?
    self.class.half_day?(@request.account, @request.applicant_id, @request.template, @request.form_data)
  end

  def apply_reclock
    date = form_dates.first
    raise WriteError, '补卡单缺少有效日期' if date.nil?

    # 审批可能滞后到窗口外——写入前按当前时限复核，防绕过（次数已在提交时把关，此处不重复计数以免误伤本单）。
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    raise WriteError, '补卡日期不能是未来日期' if date > today

    window = group.reclock_window_days
    raise WriteError, "补卡已超出 #{window} 天时限" if window.positive? && date < today - window

    mark(date, 'NORMAL')
  end

  # 写入考勤：HR 手工修正优先（source=hr 不覆盖）；整天请假不覆盖已实打卡的当天（避免「请假却有打卡」矛盾）。
  # 半天假(HALF_LEAVE)/出差(FIELD) 允许与打卡并存，不做该跳过。
  def mark(date, status, field: false)
    rec = @request.account.crm_attendance_records
                  .find_or_initialize_by(user_id: @request.applicant_id, work_date: date)
    return if rec.persisted? && rec.source == 'hr'
    return if status == 'LEAVE' && rec.clock_in_at.present?

    # 记下是哪张单写的：销假回滚只认自己写的记录，不碰别的单或 HR 改过的。
    attrs = { status: status, note: "审批联动：#{@request.title}", adjusted_by_id: @actor.id,
              source: 'approval', approval_request_id: @request.id }
    attrs[:field] = true if field
    rec.assign_attributes(attrs)
    rec.save!
  end

  def form_dates
    self.class.form_dates(@request.template, @request.form_data)
  end

  def group
    @group ||= Crm::AttendanceGroup.for_user(@request.account, @request.applicant_id)
  end
end
