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
      step = @request.current_step
      raise InvalidAction, '当前无你可审批的步骤' unless actionable?(step)

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
      # 销假单通过：回滚原单写进去的考勤（只销今天及以后的，详见 AttendanceRevokeService）。
      return revoke_original if @request.revoke_request?

      # 考勤联动：请假/补卡模板整单通过后自动写入考勤。
      Crm::AttendanceApprovalService.new(request: @request, actor: @actor).perform
      # 备用金台账联动：备用金申请/费用报销模板整单通过后自动落一笔流水。
      Crm::PettyCashApprovalService.new(request: @request, actor: @actor).perform
    end
  end

  # 销假：按销假单 form_data 里的区间回滚原单的考勤，并把原单标记为已销。
  def revoke_original
    original = @request.revokes_request
    dates = Crm::AttendanceApprovalService.form_dates(@request.template, @request.form_data)
    raise Crm::AttendanceRevokeService::RevokeError, '销假单缺少有效日期' if dates.empty?

    Crm::AttendanceRevokeService.new(
      request: original, from: dates.min, to: dates.max, actor: @actor
    ).perform
  end
end
