# 监听消息创建事件，把邮件渠道的收/发消息镜像成 CRM 邮件（Crm::Email）。
# 挂在 AsyncDispatcher（Sidekiq 内执行），失败只记日志、绝不影响原消息链路。
class CrmEmailListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.inbox&.email?

    Crm::EmailIntakeService.new(message: message).perform
  rescue StandardError => e
    Rails.logger.error "[CrmEmailListener] mirror failed for message #{message&.id}: #{e.message}"
  end
end
