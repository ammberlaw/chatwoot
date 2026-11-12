# 备用金台账联动：带 cash_kind 标记的审批单整单通过时，自动往对应台账本落一笔流水。
# - advance（备用金申请）→ 记「存入」；
# - reimburse（费用报销）→ 记「支出」。
# 落到哪本账：优先按申请单上的部门找绑定该部门的台账本；找不到就不落账（审批照常通过）。
# 台账本是财务自己建的，缺本不该反过来卡住 HR/财务的审批流程。
class Crm::PettyCashApprovalService
  KIND_DIRECTION = { 'advance' => 'IN', 'reimburse' => 'OUT' }.freeze

  def initialize(request:, actor:)
    @request = request
    @actor = actor
  end

  def perform
    direction = KIND_DIRECTION[@request.definition.cash_kind]
    return if direction.nil?

    book = resolve_book
    return log_missing_book if book.nil?

    amount = form_amount
    return if amount.nil? || amount <= 0

    book.entries.create!(
      account_id: @request.account_id,
      entry_date: Time.current.in_time_zone(Crm::AttendanceRecord::TZ).to_date,
      direction: direction,
      amount: amount,
      subject: subject,
      category: form_value('category').presence,
      handler_id: @request.applicant_id,
      remark: "审批单 ##{@request.id} 自动落账",
      oa_approval_request_id: @request.id,
      created_by_id: @actor.id
    )
  end

  private

  # 申请单带部门时按部门找本；部门没绑台账本则不落账。
  def resolve_book
    return nil if @request.department_id.blank?

    @request.account.crm_petty_cash_books.active.find_by(org_department_id: @request.department_id)
  end

  def log_missing_book
    Rails.logger.info(
      "[Crm::PettyCashApproval] request=#{@request.id} 部门 #{@request.department_id} 未绑定备用金台账本，跳过落账"
    )
  end

  # 金额字段：模板里 type=amount 的第一个字段（备用金申请=借款金额，费用报销=报销金额）。
  def form_amount
    key = Array(@request.definition.form_fields).find { |f| f['type'] == 'amount' }&.dig('key')
    value = key ? form_value(key) : nil
    BigDecimal(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # 事由：优先表单里的用途/说明类文本，取不到就退回单据标题。
  def subject
    text = %w[purpose note reason remark].filter_map { |k| form_value(k).presence }.first
    (text || @request.title).to_s.strip.truncate(120)
  end

  def form_value(key)
    (@request.form_data || {})[key].to_s
  end
end
