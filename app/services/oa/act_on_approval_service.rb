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
    # 步骤落定 + 整单状态 + 考勤写回同一事务；事务开头锁本单、锁内复检，
    # 序列化同一单并发的同意/驳回/撤回，杜绝重复推进、越级、双写考勤。
    ApplicationRecord.transaction do
      @request.lock!
      @request.freeze_definition!
      step = @request.current_step
      raise InvalidAction, '当前无你可审批的步骤' unless actionable?(step)

      step.update!(status: @decision, comment: @comment, acted_at: Time.current)
      @request.event!(@decision, actor: @actor, payload: { 'step_id' => step.id, 'comment' => @comment })
      @decision == 'rejected' ? @request.update!(status: 'rejected') : advance
    end
    # 事务外：通知失败不该回滚已经落定的审批动作（尤其 advance 里已写了考勤/备用金）。
    Oa::ApprovalNotifier.new(@request).acted
    @request
  end

  private

  def actionable?(step)
    @request.pending? && step.present? && step.status == 'pending' && step.approver_id == @actor.id &&
      %w[approved rejected].include?(@decision) && @request.account.account_users.active_members.exists?(user_id: @actor.id)
  end

  def advance
    next_step = @request.steps.where(status: 'pending')
                        .where('position > ?', @request.current_position)
                        .order(:position).first
    if next_step
      next_step.update!(assigned_at: Time.current)
      @request.update!(current_position: next_step.position)
    else
      Oa::FinalizeApprovalService.new(request: @request, actor: @actor).perform
    end
  end
end
