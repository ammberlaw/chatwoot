require 'google/cloud/translate/v3'

class Integrations::GoogleTranslate::ProcessorService
  pattr_initialize [:message!, :target_language!]

  # 语言代码 → 语言名（喂给 DeepSeek）。
  LANG_NAMES = {
    'zh_CN' => '简体中文', 'zh_TW' => '繁体中文', 'zh' => '简体中文', 'en' => 'English',
    'ja' => '日本語', 'ko' => '한국어', 'es' => 'Español', 'fr' => 'Français',
    'de' => 'Deutsch', 'ru' => 'Русский', 'pt' => 'Português', 'it' => 'Italiano',
    'ar' => 'العربية', 'vi' => 'Tiếng Việt', 'th' => 'ภาษาไทย', 'id' => 'Bahasa Indonesia',
    'tr' => 'Türkçe', 'nl' => 'Nederlands'
  }.freeze

  def perform
    content = translation_content
    return if content.blank?

    # 优先走我方 DeepSeek（管理员在「AI 设置」配了 key 即生效），免配 Google 翻译；未配则回退 Google。
    deepseek = deepseek_translate(content)
    return deepseek if deepseek.present?

    return if hook.blank?

    response = client.translate_text(
      contents: [content],
      target_language_code: bcp47_language_code,
      parent: "projects/#{hook.settings['project_id']}",
      mime_type: mime_type
    )

    return if response.translations.first.blank?

    response.translations.first.translated_text
  end

  private

  # 用我方 DeepSeek 翻译；未配 key 或出错则返回 nil（回退 Google）。
  def deepseek_translate(content)
    setting = Crm::AiSetting.for_account(message.account)
    return nil if setting.api_key.blank?

    Crm::EmailAiService.new(account: message.account)
                       .translate_text(text: content, language: language_name)
  rescue StandardError => e
    Rails.logger.warn("[GoogleTranslate->DeepSeek] #{e.class}: #{e.message}")
    nil
  end

  def language_name
    code = target_language.to_s
    LANG_NAMES[code] || LANG_NAMES[code.split(/[_-]/).first] || code
  end

  def bcp47_language_code
    target_language.tr('_', '-')
  end

  def email_channel?
    message&.inbox&.email?
  end

  def email_content
    @email_content ||= {
      html: message.content_attributes.dig('email', 'html_content', 'full'),
      text: message.content_attributes.dig('email', 'text_content', 'full'),
      content_type: message.content_attributes.dig('email', 'content_type')
    }
  end

  def html_content_available?
    email_content[:html].present?
  end

  def plain_text_content_available?
    email_content[:content_type]&.include?('text/plain') &&
      email_content[:text].present?
  end

  def translation_content
    return message.content unless email_channel?
    return email_content[:html] if html_content_available?
    return email_content[:text] if plain_text_content_available?

    message.content
  end

  def mime_type
    if email_channel? && html_content_available?
      'text/html'
    else
      'text/plain'
    end
  end

  def hook
    @hook ||= message.account.hooks.find_by(app_id: 'google_translate')
  end

  def client
    @client ||= ::Google::Cloud::Translate::V3::TranslationService::Client.new do |config|
      config.credentials = hook.settings['credentials']
    end
  end
end
