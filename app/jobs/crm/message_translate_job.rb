# 把一条会话消息的正文翻译成指定语言，结果写入 message.translations[locale_key]（供气泡同屏显示）。
# 收信自动翻译走这里（译成中文）；异步执行，失败只记日志、绝不影响消息本身。
class Crm::MessageTranslateJob < ApplicationJob
  queue_as :low

  def perform(message_id, language, locale_key)
    message = Message.find_by(id: message_id)
    return if message.nil? || message.content.blank?
    return if message.translations.present? && message.translations[locale_key].present?

    translated = Crm::EmailAiService.new(account: message.account).translate_text(text: message.content, language: language)
    return if translated.blank?

    message.update!(translations: (message.translations || {}).merge(locale_key => translated))
  rescue Crm::EmailAiService::NotConfigured
    nil # AI 未配置：静默跳过
  rescue StandardError => e
    Rails.logger.error "[Crm::MessageTranslateJob] message #{message_id}: #{e.message}"
  end
end
