# 成员权限管理：为账号成员设置系统角色（一个下拉管到底）。超级管理员与管理员（deputy_admin）可用；
# 部门负责人受限进入：只看到下属成员，且仅可为下属重置密码（不可改角色/模块/账号资料，不可碰超管与管理员）。
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
    scope = Current.account.account_users.includes(:user)
    # 部门负责人只看到下属成员。
    scope = scope.where(user_id: subordinate_user_ids) unless admin_like?
    @members = scope.order('users.name')
  end

  # 直接新建成员（免邀请链接）：建号即生效，跳过邮箱确认。仅超管/管理员。
  def create
    error = direct_create_error
    return render json: { error: error[:message] }, status: error[:status] if error

    ActiveRecord::Base.transaction do
      user = build_direct_user(direct_email)
      @member = Current.account.account_users.create!(direct_member_attrs(user))
      create_primary_membership(user)
    end
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: friendly_invalid_message(e.record) }, status: :unprocessable_entity
  end

  def update
    # 防自锁：不能修改自己的角色/权限（降级自己可能失去管理入口）。
    return render json: { error: '不能修改自己的角色' }, status: :unprocessable_entity if @member.id == Current.account_user.id
    # 防提权：管理员不可改动超级管理员，也不可把任何人设为超级管理员。
    return render json: { error: '仅超级管理员可任免超级管理员' }, status: :forbidden if escalation_attempt?
    # 部门负责人仅可为下属重置密码。
    return render json: { error: '部门负责人仅可为下属成员重置密码' }, status: :forbidden if manager_overreach?

    updates = role_updates
    return render json: { error: '无效的角色' }, status: :unprocessable_entity if updates.nil?

    updates[:module_access] = normalized_modules if params[:member].key?(:module_access)
    @member.update!(updates)
    apply_user_updates
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: friendly_invalid_message(e.record) }, status: :unprocessable_entity
  end

  private

  def ensure_admin
    return if admin_like? || Current.account_user&.crm_manager?

    render json: { error: I18n.t('errors.crm.admin_only', default: '仅超级管理员或管理员可管理成员角色') },
           status: :forbidden
  end

  def admin_like?
    Current.account_user&.administrator? || Current.account_user&.crm_deputy_admin?
  end

  # 部门负责人所辖部门（含下级）的全体成员 user_id（不含自己）。
  def subordinate_user_ids
    led = Current.account.org_departments.where(leader_id: Current.user.id).pluck(:id)
    return [] if led.empty?

    dept_ids = Org::Department.subtree_ids(Current.account, led)
    Current.account.org_memberships.where(department_id: dept_ids).pluck(:user_id).uniq - [Current.user.id]
  end

  # 部门负责人越界：目标不是下属 / 目标是超管或管理员 / 试图改密码以外的内容。
  def manager_overreach?
    return false if admin_like?

    return true unless subordinate_user_ids.include?(@member.user_id)
    return true if @member.administrator? || @member.crm_role == 'deputy_admin'

    (params[:member].keys.map(&:to_s) - ['password']).any?
  end

  def fetch_member
    @member = Current.account.account_users.find(params[:id])
  end

  # Devise 密码策略/邮箱唯一的报错缺中文翻译，映射成可读提示。
  def friendly_invalid_message(record)
    return '密码不符合要求：至少 8 位，需包含大小写字母、数字和特殊字符' if record.errors.include?(:password)
    return '该邮箱已被其他账号使用' if record.errors.include?(:email)

    record.errors.full_messages.join('；')
  end

  # 超级管理员/管理员可直接修改成员账号：姓名、登录邮箱、重置密码（改邮箱免二次确认，即时生效）。
  def apply_user_updates
    m = params[:member]
    attrs = {}
    attrs[:name] = m[:name].to_s.strip if m[:name].present?
    attrs[:email] = m[:email].to_s.strip.downcase if m[:email].present?
    attrs[:password] = m[:password] if m[:password].present?
    return if attrs.empty?

    user = @member.user
    user.skip_reconfirmation! if attrs[:email]
    user.update!(attrs)
  end

  def escalation_attempt?
    return false if Current.account_user.administrator?

    @member.administrator? || params[:member][:system_role].to_s == 'administrator'
  end

  def create_escalation_attempt?
    !Current.account_user.administrator? && params[:member][:system_role].to_s == 'administrator'
  end

  def direct_create_error
    return { message: '仅超级管理员或管理员可新建成员', status: :forbidden } unless admin_like?
    return { message: '仅超级管理员可新建超级管理员', status: :forbidden } if create_escalation_attempt?
    return { message: '无效的角色', status: :unprocessable_entity } if SYSTEM_ROLE_MAP[params[:member][:system_role].to_s].nil?
    return { message: '该邮箱已注册', status: :unprocessable_entity } if User.exists?(email: direct_email)

    nil
  end

  def direct_email
    @direct_email ||= params[:member][:email].to_s.strip.downcase
  end

  def direct_member_attrs(user)
    role, crm_role = SYSTEM_ROLE_MAP.fetch(params[:member][:system_role].to_s)
    { user_id: user.id, role: role, crm_role: crm_role, module_access: normalized_modules, inviter_id: current_user.id }
  end

  def build_direct_user(email)
    user = User.new(name: params[:member][:name].to_s.strip, email: email,
                    password: params[:member][:password], password_confirmation: params[:member][:password])
    user.skip_confirmation!
    user.save!
    user
  end

  def create_primary_membership(user)
    department_id = params[:member][:department_id].presence
    return if department_id.blank?

    department = Current.account.org_departments.find(department_id)
    Org::Membership.create!(account_id: Current.account.id, department_id: department.id,
                            user_id: user.id, is_primary: true)
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
