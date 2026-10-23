# MES 待办推到手机。
#
# 挂在 Mes::Notification 落库之后，所以收件人、权限口径全部沿用 Mes::Notifier
# 既有的判定——那套口径同时供 inbox / approval_inbox / 出库审批 / todo_count 用，
# 另写一份迟早和它们对不上（「角标说 3 条、点进去 2 条」）。
#
# message_id 用通知记录自己的 id：天然持久化，而且同一张单、同一阶段、不同收件人
# 各是一条记录，推送去重键因此自动区分到人，不会出现甲已读把乙的推送也去掉。
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
        kind: 'mes_todo', entity_id: note.production_order_id, message_id: note.id
      )
    end
  end

  private

  # 只推要人动手的：todo（有东西等你处理）和 rejected（被退回，得回去改）。
  # progress 组是周知——「这单通过了」「报工了」收到也无事可做，推了只会让人
  # 对通知脱敏，真正该处理的反而被淹掉（gm_approve! 里不发通过知会是同一个道理）。
  ACTIONABLE_GROUPS = %w[todo rejected].freeze

  def pushable?(note)
    # 已办结就别再吵人。read_at 是 Mes::Notifier.resolve 在真正的办结动作
    # （审批通过/驳回、确认 BOM、接单、出库）时打的，不是「点开看过」。
    # 正常路径上 job 几毫秒就跑了，这条是给失败重试用的——DeliveryError 退避重试
    # 最多跨好几分钟，那期间这件事很可能已经有人处理掉了。
    return false if note.read_at.present?
    return false if Mes::Notification::ERP_KINDS.include?(note.kind)
    # entity_id 必须是正整数，App 端缺了会整条丢弃；而 mes_todo 点开要落到
    # 生产待办列表，挂不上订单的那几类（现货出库审批回执等）本来也不在那张列表里。
    return false if note.production_order_id.blank?
    return false unless ACTIONABLE_GROUPS.include?(Mes::Notification::GROUP_BY_KIND[note.kind])

    AccountUser.exists?(account_id: note.account_id, user_id: note.recipient_id, deactivated_at: nil)
  end
end
