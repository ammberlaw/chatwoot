# 收到对方消息时，若该会话开启自动翻译，把来信自动译成中文（写入 message.translations 供气泡同屏）。
# 挂 AsyncDispatcher（Sidekiq 内执行），失败只记日志、绝不影响原消息链路。
class CrmTranslateListener < BaseListener
  MY_LANGUAGE = '简体中文'.freeze
  MY_LOCALE_KEY = 'zh_CN'.freeze

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message&.incoming?
    return if message.content.blank?
    return unless auto_translate_on?(message.conversation)

    Crm::MessageTranslateJob.perform_later(message.id, MY_LANGUAGE, MY_LOCALE_KEY)
  rescue StandardError => e
    Rails.logger.error "[CrmTranslateListener] message #{message&.id}: #{e.message}"
  end

  private

  # 会话级开关：additional_attributes['auto_translate']，默认开（未显式设为 false 即视为开）。
  def auto_translate_on?(conversation)
    conversation.additional_attributes.fetch('auto_translate', true) != false
  end
end
