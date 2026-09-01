# frozen_string_literal: true

# Base service for LLM operations using RubyLLM.
# New features should inherit from this class.
class Llm::BaseAiService
  DEFAULT_MODEL = Llm::Config::DEFAULT_MODEL
  DEFAULT_TEMPERATURE = 1.0

  attr_reader :model, :temperature

  def initialize(feature: nil, account: nil, fallback_model: nil)
    @llm_feature = feature
    @llm_account = account
    @fallback_model = fallback_model

    Llm::Config.initialize!
    setup_model
    setup_temperature
  end

  def chat(model: @model, temperature: @temperature)
    # 已在 CRM「AI 设置」配了我方 DeepSeek 时，Captain 智能体聊天（会话「问 AI 助手」）也走它。
    return deepseek_chat(temperature) if crm_ai_setting

    RubyLLM.chat(model: model).with_temperature(temperature)
  end

  private

  # 我方 DeepSeek 配置（管理员在「AI 设置」页那把 key）。未配置返回 nil，保持原生行为。
  def crm_ai_setting
    return @crm_ai_setting if defined?(@crm_ai_setting)

    setting = @llm_account && Crm::AiSetting.for_account(@llm_account)
    @crm_ai_setting = setting&.api_key.present? ? setting : nil
  end

  # DeepSeek 的模型名不在 RubyLLM 注册表，需 assume_model_exists；且只认 system 角色。
  def deepseek_chat(temperature)
    context = RubyLLM.context do |config|
      config.openai_api_key = crm_ai_setting.api_key
      config.openai_api_base = crm_ai_setting.api_base.presence || Crm::EmailAiService::DEFAULT_API_BASE
      config.openai_use_system_role = true
    end
    context.chat(
      model: crm_ai_setting.model.presence || Crm::EmailAiService::DEFAULT_MODEL,
      provider: :openai, assume_model_exists: true
    ).with_temperature(temperature)
  end

  # Strips markdown code fences (```json ... ``` or ``` ... ```) that some
  # LLM providers/gateways wrap around JSON responses despite response_format hints.
  def sanitize_json_response(response)
    return response if response.nil?

    response.strip.sub(/\A```(?:\w*)\s*\n?/, '').sub(/\n?\s*```\s*\z/, '').strip
  end

  def setup_model
    route = feature_route
    return @model = route[:model] if account_override_route?(route)

    @model = @fallback_model.presence || installation_model.presence || route&.dig(:model) || DEFAULT_MODEL
  end

  def feature_route
    return if @llm_feature.blank?

    Llm::FeatureRouter.resolve(feature: @llm_feature, account: @llm_account)
  end

  def account_override_route?(route)
    route&.dig(:source) == :account_override
  end

  def installation_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  end

  def setup_temperature
    @temperature = DEFAULT_TEMPERATURE
  end
end
