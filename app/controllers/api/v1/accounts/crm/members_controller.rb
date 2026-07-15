# 成员权限管理：为账号成员设置系统角色（一个下拉管到底）。超级管理员与管理员（deputy_admin）可用。
# 系统角色 → 底层 Chatwoot role + crm_role 的映射：
#   管理员 = administrator；副管理员/部门负责人/业务员 = agent + 对应 crm_role；无 = agent（不进入 CRM）。
class Api::V1::Accounts::Crm::MembersController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_admin
  before_action :fetch_member, only: [:update]

  SYSTEM_ROLE_MAP = {
    'administrator' => [:administrator, nil],
    'deputy_admin' => [:agent, 'deputy_admin'],
    'manager' => [:agent, 'manager'],
    'sales' => [:agent, 'sales'],
    '' => [:agent, nil]
  }.freeze

  def index
    @members = Current.account.account_users.includes(:user).order('users.name')
  end

  def update
    # 防自锁：不能修改自己的角色/权限（降级自己可能失去管理入口）。
    return render json: { error: '不能修改自己的角色' }, status: :unprocessable_entity if @member.id == Current.account_user.id
    # 防提权：管理员不可改动超级管理员，也不可把任何人设为超级管理员。
    return render json: { error: '仅超级管理员可任免超级管理员' }, status: :forbidden if escalation_attempt?

    updates = role_updates
    return render json: { error: '无效的角色' }, status: :unprocessable_entity if updates.nil?

    updates[:module_access] = normalized_modules if params[:member].key?(:module_access)
    @member.update!(updates)
  end

  private

  def ensure_admin
    return if Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?

    render json: { error: I18n.t('errors.crm.admin_only', default: '仅超级管理员或管理员可管理成员角色') },
           status: :forbidden
  end

  def fetch_member
    @member = Current.account.account_users.find(params[:id])
  end

  def escalation_attempt?
    return false if Current.account_user.administrator?

    @member.administrator? || params[:member][:system_role].to_s == 'administrator'
  end

  # system_role 未传 → 不改角色（空 hash）；传了但非法 → nil（422）。
  def role_updates
    return {} unless params[:member].key?(:system_role)

    mapping = SYSTEM_ROLE_MAP[params[:member][:system_role].to_s]
    return nil unless mapping

    { role: mapping[0], crm_role: mapping[1] }
  end

  def normalized_modules
    Array(params[:member][:module_access]).map(&:to_s) & AccountUser::MODULES
  end
end
