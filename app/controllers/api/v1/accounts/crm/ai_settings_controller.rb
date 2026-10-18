# 邮件 AI 助手设置（单行，仅管理员）：show 返回当前配置（api_key 脱敏，只回是否已配 + 尾 4 位），
# update 保存，test 用表单里的值（未保存也行）验一把连通性。
class Api::V1::Accounts::Crm::AiSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    @setting = Crm::AiSetting.for_account(Current.account)
    @usage = month_usage
  end

  def update
    @setting = Crm::AiSetting.for_account(Current.account)
    attrs = setting_params
    # api_key / apollo_api_key 留空 = 保持原值不变（前端不回显完整 key，改其它设置时不必重填）。
    attrs = attrs.except(:api_key) if attrs[:api_key].blank?
    attrs = attrs.except(:apollo_api_key) if attrs[:apollo_api_key].blank?
    @setting.assign_attributes(attrs)
    @setting.save!
    render :show
  end

  # 连接测试：优先用请求里传来的（表单当前值），空则回退已保存配置。
  def test
    service = Crm::EmailAiService.new(
      account: Current.account,
      api_key: params[:api_key].presence,
      api_base: params[:api_base].presence,
      model: params[:model].presence
    )
    service.test!
    render json: { ok: true, message: '连接正常，AI 可用' }
  rescue Crm::EmailAiService::NotConfigured => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    # 探测动作：连不上/鉴权失败/模型不存在等都翻译成友好提示，不抛 500。
    render json: { ok: false, message: "连接失败：#{e.message}" }, status: :unprocessable_entity
  end

  private

  # 本月用量：开了新询盘初筛之后它会自动跑、自动花钱，没有数就既谈不上调优，
  # 也判断不了该不该给某个人开。只统计 assistant 那条（一问一答算一轮，
  # token 是整轮含工具来回的合计，见 Crm::Agent::Runner#usage_attrs）。
  def month_usage
    since = Time.current.beginning_of_month
    convs = Current.account.crm_agent_conversations
    rows = Crm::AgentMessage.where(conversation_id: convs.select(:id))
                            .where(role: 'assistant', created_at: since..)
    {
      rounds: rows.count,
      input_tokens: rows.sum(:input_tokens),
      output_tokens: rows.sum(:output_tokens),
      avg_seconds: (rows.average(:duration_ms).to_f / 1000).round(1),
      # 失败的那几轮：会话停在 FAILED，last_error 里有原因
      failed: convs.where(status: 'FAILED', updated_at: since..).count,
      users: convs.where(id: rows.select(:conversation_id)).distinct.count(:user_id)
    }
  end

  def check_authorization
    authorize(Crm::AiSetting)
  end

  def setting_params
    # agent_user_ids 是数组：谁能用 CRM 的 AI 助手（管理员恒可用，见 Crm::AiSetting.agent_allowed?）
    params.require(:setting).permit(:api_key, :model, :api_base, :apollo_api_key,
                                    :inquiry_triage_enabled, agent_user_ids: [])
  end
end
