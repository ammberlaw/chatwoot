# 邮件 AI 助手设置（单行，仅管理员）：show 返回当前配置（api_key 脱敏，只回是否已配 + 尾 4 位），
# update 保存，test 用表单里的值（未保存也行）验一把连通性。
class Api::V1::Accounts::Crm::AiSettingsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  def show
    @setting = Crm::AiSetting.for_account(Current.account)
  end

  def update
    @setting = Crm::AiSetting.for_account(Current.account)
    attrs = setting_params
    # api_key 留空 = 保持原 key 不变（前端不回显完整 key，改模型/端点时不必重填）。
    attrs = attrs.except(:api_key) if attrs[:api_key].blank?
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

  def check_authorization
    authorize(Crm::AiSetting)
  end

  def setting_params
    params.require(:setting).permit(:api_key, :model, :api_base)
  end
end
