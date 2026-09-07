# 会话自动翻译：保存会话级设置（开关 + 对方语言）+ 外发时把中文译成对方语言。
# 收信自动译中文走 CrmTranslateListener（服务端），不经这里。
class Api::V1::Accounts::Crm::ConversationTranslationController < Api::V1::Accounts::Crm::BaseController
  before_action :set_conversation

  rescue_from Crm::EmailAiService::NotConfigured do |e|
    render json: { message: e.message }, status: :unprocessable_entity
  end

  rescue_from RubyLLM::Error, Faraday::Error do |e|
    render json: { message: "翻译服务出错：#{e.message}" }, status: :bad_gateway
  end

  # 保存会话级翻译设置：auto_translate（自动翻译开关）+ target_language（对方语言）。
  def settings
    attrs = @conversation.additional_attributes || {}
    attrs['auto_translate'] = ActiveModel::Type::Boolean.new.cast(params[:auto_translate]) unless params[:auto_translate].nil?
    attrs['target_language'] = params[:target_language].to_s if params.key?(:target_language)
    @conversation.update!(additional_attributes: attrs)
    render json: { auto_translate: attrs.fetch('auto_translate', true), target_language: attrs['target_language'] }
  end

  # 外发翻译：把中文文本译成对方语言（默认取会话 target_language，language 参数可覆盖）。
  def translate
    text = params[:text].to_s
    return render json: { content: '' } if text.strip.blank?

    language = params[:language].presence || @conversation.additional_attributes&.dig('target_language').presence || '英语'
    content = Crm::EmailAiService.new(account: Current.account).translate_text(text: text, language: language)
    render json: { content: content }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end
end
