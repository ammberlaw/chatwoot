# 考勤审批联动：带考勤联动标记的审批单（请假/补卡）整单通过时自动写入考勤。
# - leave：取表单日期字段的最早/最晚值为区间，区间内每个工作日标「请假」；
# - reclock：取表单第一个日期字段的值，该天补为「正常」。
# 写入等同 HR 修正（adjusted_by=终审人，留审计），之后打卡不会覆盖。
class Crm::AttendanceApprovalService
  MAX_LEAVE_SPAN_DAYS = 62

  # 模板里 type=date 字段在 form_data 中的取值（按字段定义顺序）。
  def self.form_dates(template, form_data)
    keys = Array(template.form_fields).select { |f| f['type'] == 'date' }.pluck('key')
    keys.filter_map do |k|
      Date.parse(form_data[k].to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  # 补卡规则校验（按申请人所属考勤组）：返回错误文案或 nil。
  # 时限：只能补 window 天内的卡（0=不限）；上限：当月（按补卡日期归月）已提交/已通过的补卡单数（0=不允许补卡）。
  def self.reclock_violation(account, applicant_id, date)
    group = Crm::AttendanceGroup.for_user(account, applicant_id)
    today = Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date
    return '补卡日期不能是未来日期' if date > today
    return '该考勤组不允许补卡' if group.reclock_limit.zero?
    return "只能申请 #{group.reclock_window_days} 天内的补卡" if group.reclock_window_days.positive? && date < today - group.reclock_window_days

    used = reclock_used_in_month(account, applicant_id, date)
    return "当月补卡次数已达上限（#{group.reclock_limit} 次）" if used >= group.reclock_limit

    nil
  end

  # 当月已用补卡次数：审批中/已通过的补卡单，按其补卡日期归月统计。
  def self.reclock_used_in_month(account, applicant_id, date)
    account.oa_approval_requests
           .joins(:template)
           .where(oa_approval_templates: { attendance_kind: 'reclock' },
                  applicant_id: applicant_id, status: %w[pending approved])
           .count do |r|
      d = form_dates(r.template, r.form_data).first
      d && d.beginning_of_month == date.beginning_of_month
    end
  end

  def initialize(request:, actor:)
    @request = request
    @actor = actor
  end

  def perform
    kind = @request.template.attendance_kind
    return if kind.blank?

    dates = form_dates
    return if dates.empty?

    case kind
    when 'leave' then apply_leave(dates)
    when 'reclock' then mark(dates.first, 'NORMAL')
    end
  end

  private

  def apply_leave(dates)
    range = dates.min..dates.max
    return if (range.last - range.first).to_i > MAX_LEAVE_SPAN_DAYS

    range.each do |date|
      mark(date, 'LEAVE') if group.work_day?(date)
    end
  end

  def mark(date, status)
    rec = @request.account.crm_attendance_records
                  .find_or_initialize_by(user_id: @request.applicant_id, work_date: date)
    rec.assign_attributes(status: status, note: "审批联动：#{@request.title}", adjusted_by_id: @actor.id)
    rec.save!
  end

  def form_dates
    self.class.form_dates(@request.template, @request.form_data)
  end

  def group
    @group ||= Crm::AttendanceGroup.for_user(@request.account, @request.applicant_id)
  end
end
