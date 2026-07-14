# CRM 成员权限管理：列出账号成员并为其分配 CRM 角色（主管/业务员/无）。仅系统管理员可用。
# 系统管理员自动是 CRM 管理员（全权），此处不改其 crm_role。
class Api::V1::Accounts::Crm::MembersController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_admin
  before_action :fetch_member, only: [:update]

  def index
    @members = Current.account.account_users.includes(:user).order('users.name')
  end

  def update
    @member.update!(crm_role: normalized_crm_role)
  end

  private

  def ensure_admin
    return if Current.account_user&.administrator?

    render json: { error: I18n.t('errors.crm.admin_only', default: '仅管理员可管理 CRM 角色') },
           status: :forbidden
  end

  def fetch_member
    @member = Current.account.account_users.find(params[:id])
  end

  # 空串/无 → nil（清除 CRM 权限）；其余按模型枚举校验。
  def normalized_crm_role
    role = params.require(:member).permit(:crm_role)[:crm_role].presence
    role
  end
end
