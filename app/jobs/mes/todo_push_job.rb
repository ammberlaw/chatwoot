# MES 待办推到手机。
#
# 挂在 Mes::Notification 落库之后，所以收件人、权限口径全部沿用 Mes::Notifier
# 既有的判定——那套口径同时供 inbox / approval_inbox / 出库审批 / todo_count 用，
# 另写一份迟早和它们对不上（「角标说 3 条、点进去 2 条」）。
#
# entity_id / message_id 都用通知记录自己的 id：天然持久化，而且同一张单、同一阶段、
# 不同收件人各是一条记录，推送去重键因此自动区分到人，不会出现甲已读把乙的推送也去掉。
# 不用 production_order_id——点开 mes_todo 固定落 /mes/todo 由服务端重载当前用户待办，
# 根本不拿 entity_id 寻址；而现货出库、现货采购这些待办压根不挂生产订单，
# 拿它当 entity_id 等于把这些人的推送全掐掉。
class Mes::TodoPushJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  def perform(notification_id)
    note = Mes::Notification.find_by(id: notification_id)
    return unless note && pushable?(note)

    NotificationSubscription.native.where(user_id: note.recipient_id).find_each do |subscription|
      next unless subscription.subscription_attributes['account_id'].to_i == note.account_id

      Notification::NativePushService.new.deliver(
        subscription: subscription, account_id: note.account_id, user_id: note.recipient_id,
        kind: 'mes_todo', entity_id: note.id, message_id: note.id
      )
    end
  end

  private

  # 只推要人动手的：todo（有东西等你处理）和 rejected（被退回，得回去改）。
  # progress 组是周知——「这单通过了」「报工了」收到也无事可做，推了只会让人
  # 对通知脱敏，真正该处理的反而被淹掉（gm_approve! 里不发通过知会是同一个道理）。
  ACTIONABLE_GROUPS = %w[todo rejected].freeze

  # 这些 kind 在统一可办出口（Mes::TodoList）里有对应的 action_type，
  # 重试时可以按「这个人现在还有没有这件事要办」精确复核。
  # 没列进来的（待下发采购、成品待清点、单据被退回等）出口还没覆盖，
  # 维持原有判定——宁可多推一条，也不能因为出口没覆盖就把人家的推送静默掐掉。
  KIND_TO_ACTION = {
    'approval_pending' => 'production_approval',
    'stage_assigned' => 'stage_ack',
    'bom_reconfirm' => 'confirm_bom',
    'sales_return_pending' => 'sales_return_confirm',
    'po_approval_pending' => 'purchase_approval',
    'shipment_approval_pending' => 'shipment_approval'
  }.freeze

  def pushable?(note)
    # 已办结就别再吵人。read_at 是 Mes::Notifier.resolve 在真正的办结动作
    # （审批通过/驳回、确认 BOM、接单、出库）时打的，不是「点开看过」。
    return false if note.read_at.present?
    return false if Mes::Notification::ERP_KINDS.include?(note.kind)
    return false unless ACTIONABLE_GROUPS.include?(Mes::Notification::GROUP_BY_KIND[note.kind])
    return false unless AccountUser.exists?(account_id: note.account_id, user_id: note.recipient_id,
                                            deactivated_at: nil)

    still_actionable?(note)
  end

  # 重试前按**当下**复核：这个人现在还有没有这件事要办。
  #
  # read_at 只能告诉我们「有没有人办结」，告不了「这个人还有没有权限办」。
  # DeliveryError 退避重试最多跨好几分钟，那期间审批可能流转到下一级、阶段负责人
  # 可能换人、这个人可能被撤权——再推给他，他点开也办不了。
  #
  # 只在重试时跑：首次执行就在通知落库后几毫秒，状态不可能变，而建一次 TodoList
  # 要好几次查询，没必要摊到正常路径上。
  def still_actionable?(note)
    return true if executions <= 1

    action = KIND_TO_ACTION[note.kind]
    return true if action.nil?

    au = AccountUser.find_by(account_id: note.account_id, user_id: note.recipient_id, deactivated_at: nil)
    Mes::TodoList.new(account: note.account, account_user: au).items.any? do |i|
      # 按单号比对：通知标题里一定带着单号（「待审核：生产出库 DN-20261022-02」），
      # 这也是 Mes::Notifier.resolve 认单的同一套办法（title_like）。
      i[:action_type] == action && i[:subject_no].present? && note.title.to_s.include?(i[:subject_no])
    end
  end
end
