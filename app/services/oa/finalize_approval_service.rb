# Called while the approval request is locked, for manual and explicitly automatic approval alike.
class Oa::FinalizeApprovalService
  def initialize(request:, actor:)
    @request = request
    @actor = actor
  end

  def perform
    return if @request.finalized_at

    Oa::FormValidator.new(account: @request.account, applicant: @request.applicant, definition: @request.definition,
                          form_data: @request.form_data, department_id: @request.department_id, revoke: @request.revoke_request?).validate_values!
    result = {}
    if @request.revoke_request?
      dates = Crm::AttendanceApprovalService.form_dates(@request.definition, @request.form_data)
      raise Crm::AttendanceRevokeService::RevokeError, '销假单缺少有效日期' if dates.empty?

      Crm::AttendanceRevokeService.new(request: @request.revokes_request, from: dates.min, to: dates.max, actor: @actor).perform
      result['attendance'] = 'revoked'
    else
      Crm::AttendanceApprovalService.new(request: @request, actor: @actor).perform
      entry = Crm::PettyCashApprovalService.new(request: @request, actor: @actor).perform
      if @request.definition.cash_kind.present?
        result['cash'] = entry ? 'recorded' : 'not_configured'
        result['cash_entry_id'] = entry&.id
        result['notice'] = '部门未绑定备用金台账本，未自动落账，请联系财务' unless entry
      end
      result['attendance'] = 'processed' if @request.definition.attendance_kind.present?
    end
    @request.update!(status: 'approved', finalized_at: Time.current, integration_result: result)
  end
end
