class Chat::MobilePushJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  def perform(message_id)
    message = Chat::Message.find_by(id: message_id)
    return unless message

    kind, entity_id = push_target(message)
    return if kind.nil?

    NotificationSubscription.native.where(user_id: unread_member_ids(message)).find_each do |subscription|
      next unless subscription.subscription_attributes['account_id'].to_i == message.account_id

      Notification::NativePushService.new.deliver(
        subscription: subscription, account_id: message.account_id, user_id: subscription.user_id,
        kind: kind, conversation_id: message.conversation_id, entity_id: entity_id, message_id: message.id
      )
    end
  end

  private

  # Membership and read state are checked when the job runs, after the message commit.
  def unread_member_ids(message)
    members = message.conversation.participants.where.not(user_id: message.sender_id)
                     .where('COALESCE(last_read_message_id, 0) < ?', message.id)
                     .pluck(:user_id)
    AccountUser.where(account_id: message.account_id, user_id: members, deactivated_at: nil).pluck(:user_id)
  end

  # 「系统通知」挂着销售订单发出的提醒（新单待审 / 改后重提 / 通过 / 驳回）走独立 kind，
  # 点推送直接落到那张单、当场能审，而不是落进聊天只看到一行字。
  #
  # 只认系统通知这一个发送人：同事在团队沟通里手动引用一张订单说「这单你看下」，
  # 那是会话消息，点开必须进聊天看他说了什么，不能跳走。
  def push_target(message)
    return ['team', nil] if message.ref_id.blank?
    return ['team', nil] unless message.sender_id == Crm::SystemUser.existing_id_for(message.account_id)

    case message.ref_type
    when 'sales_order' then ['sales_order_approval', message.ref_id]
    when 'oa_approval' then ['approval', message.ref_id]
    # 新询盘初筛挂的也是 email ref，但新邮件本身已由 Crm::MailPushJob 推过一条了
    # （kind='mail'），这里再推一条就是同一封信响两次。初筛那 600 字 AI 分析
    # 本来就该在 Web 上细看，不适合塞进锁屏。
    when 'email' then nil
    else ['team', nil]
    end
  end
end
