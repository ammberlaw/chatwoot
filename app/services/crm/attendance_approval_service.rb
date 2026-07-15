# 考勤审批联动：带考勤联动标记的审批单（请假/补卡）整单通过时自动写入考勤。
# - leave：取表单日期字段的最早/最晚值为区间，区间内每个工作日标「请假」；
# - reclock：取表单第一个日期字段的值，该天补为「正常」。
# 写入等同 HR 修正（adjusted_by=终审人，留审计），之后打卡不会覆盖。
class Crm::AttendanceApprovalService
  MAX_LEAVE_SPAN_DAYS = 62

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
      mark(date, 'LEAVE') if setting.work_day?(date)
    end
  end

  def mark(date, status)
    rec = @request.account.crm_attendance_records
                  .find_or_initialize_by(user_id: @request.applicant_id, work_date: date)
    rec.assign_attributes(status: status, note: "审批联动：#{@request.title}", adjusted_by_id: @actor.id)
    rec.save!
  end

  # 模板里 type=date 字段在 form_data 中的取值（按字段定义顺序）。
  def form_dates
    keys = Array(@request.template.form_fields).select { |f| f['type'] == 'date' }.pluck('key')
    keys.filter_map do |k|
      value = @request.form_data[k]
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end

  def setting
    @setting ||= Crm::AttendanceSetting.for_account(@request.account)
  end
end
