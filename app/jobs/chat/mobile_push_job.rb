class Chat::MobilePushJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  def perform(message_id)
    message = Chat::Message.find_by(id: message_id)
    return unless message

    conversation = message.conversation
    # Membership and read state are checked when the job runs, after the message commit.
    members = conversation.participants.where.not(user_id: message.sender_id)
                          .where('COALESCE(last_read_message_id, 0) < ?', message.id)
                          .pluck(:user_id)
    active_members = AccountUser.where(account_id: message.account_id, user_id: members, deactivated_at: nil).pluck(:user_id)
    NotificationSubscription.native.where(user_id: active_members).find_each do |subscription|
      next unless subscription.subscription_attributes['account_id'].to_i == message.account_id

      Notification::NativePushService.new.deliver(
        subscription: subscription, account_id: message.account_id, user_id: subscription.user_id,
        kind: 'team', conversation_id: message.conversation_id, message_id: message.id
      )
    end
  end
end
