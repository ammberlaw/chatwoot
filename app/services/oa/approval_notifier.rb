# OA 审批流转提醒：谁该知道这单动了。
#
# 在这之前 OA 整条链一声不响——提交完只能自己去问审批人看没看，审批人也只能
# 靠每天翻一遍审批列表。销售订单审批补过同样的课（见 Crm::SalesOrderApprover）。
#
# 一律以「系统通知」名义发团队沟通单聊，带 oa_approval ref 卡片可点；
# 手机那头由 Chat::MobilePushJob 认出这个 ref 转成 kind='approval' 的原生推送。
# 发送失败在 Chat::NotifyService 内部兜住，不会影响审批本身。
class Oa::ApprovalNotifier
  def initialize(request)
    @request = request
  end

  # 提交 / 改单后重建审批链：提醒此刻该他办的人。
  # 空流程直接通过的单没有审批人，不吵人。
  def submitted(resubmit: false)
    return unless @request.pending?

    notify(current_approver_id, "【OA审批】#{resubmit ? '改后重新提交' : '新单待审批'}：#{label}（#{applicant_name}）", '待审批')
  end

  # 同意或驳回之后。落到哪一步由单子自己的状态说了算，不用调用方传：
  # 还在 pending = 流转到了下一节点，提醒下一个人；
  # 已 approved / rejected = 整单有结果了，提醒申请人。
  def acted
    case @request.status
    when 'pending' then notify(current_approver_id, "【OA审批】轮到你审批：#{label}（#{applicant_name}）", '待审批')
    when 'approved' then notify(@request.applicant_id, "【OA审批】#{label} 已通过", '已通过')
    when 'rejected' then notify(@request.applicant_id, "【OA审批】#{label} 被驳回#{reject_suffix}", '已驳回')
    end
  end

  # 申请人撤回：告诉本来等着审的人别审了。
  # approver_id 必须是撤回**之前**抓的——撤回后单子不再 pending，current_step 问不出人来。
  def canceled(approver_id)
    notify(approver_id, "【OA审批】#{label} 已被 #{applicant_name} 撤回，无需再审", '已撤回')
  end

  private

  def notify(target_id, text, subtitle)
    return if target_id.blank?

    Chat::NotifyService.new(account: @request.account, sender: Crm::SystemUser.for(@request.account))
                       .notify(target_id, text, ref: ref_payload(subtitle))
  end

  def ref_payload(subtitle)
    { type: 'oa_approval', id: @request.id, label: 'OA审批', title: label,
      subtitle: "#{applicant_name} · #{subtitle}" }
  end

  def current_approver_id = @request.current_step&.approver_id

  def label = [@request.template&.name, @request.title].compact_blank.uniq.join(' · ')

  def applicant_name = @request.applicant&.crm_display_name

  # 驳回意见写进正文——「被驳回」三个字不说原因，申请人还得点进来才知道改什么。
  def reject_suffix
    comment = @request.steps.where(status: 'rejected').order(:position).last&.comment
    comment.present? ? "：#{comment}" : ''
  end
end
