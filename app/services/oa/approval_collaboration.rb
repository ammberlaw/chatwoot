class Oa::ApprovalCollaboration
  class RateLimited < StandardError; end

  def initialize(request:, actor:, account_user:)
    @request = request
    @actor = actor
    @membership = account_user
  end

  def remind!
    @request.with_lock do
      raise Pundit::NotAuthorizedError unless @request.applicant_id == @actor.id || manager?
      raise Oa::FormValidator::InvalidForm, '该申请已结束，无需催办' unless @request.pending?
      raise RateLimited, '已经催办过，请一小时后再试' if @request.last_reminded_at && @request.last_reminded_at > 1.hour.ago

      target = @request.current_step&.approver_id
      raise Oa::FormValidator::InvalidForm, '当前审批人已停用，请管理员转交' unless @request.account.account_users.active_members.exists?(user_id: target)

      @request.update!(last_reminded_at: Time.current)
      @request.event!('reminded', actor: @actor, payload: { 'target_id' => target })
    end
    Oa::ApprovalNotifier.new(@request).reminded
    @request
  end

  def transfer!(target_id, reason)
    raise Pundit::NotAuthorizedError unless manager?
    raise Oa::FormValidator::InvalidForm, '请填写转交原因' if reason.to_s.strip.empty?

    target = @request.account.account_users.active_members.find_by!(user_id: target_id)
    raise Oa::FormValidator::InvalidForm, '不能转交给申请人本人' if target.user_id == @request.applicant_id

    @request.with_lock do
      step = @request.current_step
      raise Oa::FormValidator::InvalidForm, '申请已结束或没有可转交步骤' unless @request.pending? && step&.status == 'pending'
      raise Oa::FormValidator::InvalidForm, '目标成员已经是当前审批人' if step.approver_id == target.user_id

      previous = step.approver_id
      step.update!(approver_id: target.user_id, assigned_at: Time.current)
      @request.update!(last_reminded_at: nil)
      payload = { 'from_id' => previous, 'to_id' => target.user_id, 'reason' => reason,
                  'from_name' => User.find_by(id: previous)&.crm_display_name, 'to_name' => target.user.crm_display_name }
      @request.event!('transferred', actor: @actor, payload: payload)
    end
    Oa::ApprovalNotifier.new(@request).submitted(resubmit: true)
    @request
  end

  def manager?
    @membership.administrator? || @membership.crm_deputy_admin?
  end
end
