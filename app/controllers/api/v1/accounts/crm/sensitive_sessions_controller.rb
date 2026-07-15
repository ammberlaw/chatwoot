# 敏感区二次验证：进入员工档案/薪资配置前重输登录密码，通过后 15 分钟内免验。
class Api::V1::Accounts::Crm::SensitiveSessionsController < Api::V1::Accounts::Crm::BaseController
  def show
    render json: { active: Crm::SensitiveSession.active?(Current.account, current_user) }
  end

  def create
    return render json: { error: '密码不正确' }, status: :unauthorized unless current_user.valid_password?(params[:password].to_s)

    Crm::SensitiveSession.grant(Current.account, current_user)
    render json: { active: true }
  end
end
