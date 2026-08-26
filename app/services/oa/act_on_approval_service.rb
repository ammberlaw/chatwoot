# 审批动作：当前审批人对当前步骤同意/驳回。
# 同意 → 前进到下一待办步骤，无则整单通过；驳回 → 整单驳回。
class Oa::ActOnApprovalService
  class InvalidAction < StandardError; end

  def initialize(request:, actor:, decision:, comment: nil)
    @request = request
    @actor = actor
    @decision = decision
    @comment = comment
  end

  def perform
    step = @request.current_step
    raise InvalidAction, '当前无你可审批的步骤' unless actionable?(step)

    # 步骤落定 + 整单状态 + 考勤写回同一事务：写回失败则整单不通过，绝不出现「已通过但考勤没写/只写一半」。
    ApplicationRecord.transaction do
      step.update!(status: @decision, comment: @comment, acted_at: Time.current)
      @decision == 'rejected' ? @request.update!(status: 'rejected') : advance
    end
    @request
  end

  private

  def actionable?(step)
    @request.pending? && step.present? && step.status == 'pending' && step.approver_id == @actor.id &&
      %w[approved rejected].include?(@decision)
  end

  def advance
    next_step = @request.steps.where(status: 'pending')
                        .where('position > ?', @request.current_position)
                        .order(:position).first
    if next_step
      @request.update!(current_position: next_step.position)
    else
      @request.update!(status: 'approved')
      # 考勤联动：请假/补卡模板整单通过后自动写入考勤。
      Crm::AttendanceApprovalService.new(request: @request, actor: @actor).perform
    end
  end
end
