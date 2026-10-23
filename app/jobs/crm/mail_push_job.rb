# 新入站邮件推到手机。
#
# 不发站内通知：邮件一天几十封，每封落一条「系统通知」消息会把团队沟通刷爆，
# 而 Web 端邮件模块本来就有未读角标。所以这条路绕开 Chat::Message 直接发原生推送。
#
# 推给 email.owner_id——这封信实际进了谁的邮箱，不是客户负责人。两者常常不是
# 同一个人（客户发到总箱 info@、而客户挂在某业务员名下），推给负责人的话，
# 他因为邮件可见性根本打不开那封信（Crm::EmailIngestion#maybe_create_reply_reminder
# 里记着同样的教训）。
class Crm::MailPushJob < ApplicationJob
  queue_as :default
  retry_on Notification::NativePushService::DeliveryError, wait: :polynomially_longer, attempts: 5

  # 首次配置邮箱会一次抓回几百封历史邮件，那是补录不是新信，不能挨个推。
  # 放到 24 小时是为了不误杀——抓取卡住几小时后补上的信仍然该提醒。
  BACKFILL_CUTOFF = 24.hours

  def perform(email_id)
    email = Crm::Email.find_by(id: email_id)
    return unless email && pushable?(email)

    NotificationSubscription.native.where(user_id: email.owner_id).find_each do |subscription|
      next unless subscription.subscription_attributes['account_id'].to_i == email.account_id

      Notification::NativePushService.new.deliver(
        subscription: subscription, account_id: email.account_id, user_id: subscription.user_id,
        kind: 'mail', entity_id: email.id, message_id: email.id
      )
    end
  end

  private

  def pushable?(email)
    return false unless email.folder == 'INBOX' && email.owner_id.present?
    return false if (email.email_date || email.created_at) < BACKFILL_CUTOFF.ago

    AccountUser.exists?(account_id: email.account_id, user_id: email.owner_id, deactivated_at: nil)
  end
end
