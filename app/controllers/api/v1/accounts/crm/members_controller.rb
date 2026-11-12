# 成员权限管理：为账号成员设置系统角色（一个下拉管到底）。超级管理员与管理员（deputy_admin）可用；
# 部门负责人受限进入：只看到下属成员，且仅可为下属重置密码（不可改角色/模块/账号资料，不可碰超管与管理员）。
# 系统角色 → 底层 Chatwoot role + crm_role 的映射：
#   管理员 = administrator；副管理员/部门负责人/业务员 = agent + 对应 crm_role；无 = agent（不进入 CRM）。
class Api::V1::Accounts::Crm::MembersController < Api::V1::Accounts::Crm::BaseController
  # 人事角色不走 CRM 门禁（无 CRM 数据权限），本控制器由 ensure_admin 把关。
  skip_before_action :ensure_crm_access
  before_action :ensure_admin
  before_action :fetch_member, only: [:update, :deactivate, :reactivate, :destroy]

  SYSTEM_ROLE_MAP = {
    'administrator' => [:administrator, nil],
    'deputy_admin' => [:agent, 'deputy_admin'],
    'manager' => [:agent, 'manager'],
    'sales' => [:agent, 'sales'],
    'hr' => [:agent, 'hr'], # 人事：组织/绩效/成员管理全套，无 CRM 销售数据
    'member' => [:agent, nil], # 普通成员（直接建号/邀请用显式键）
    '' => [:agent, nil]
  }.freeze

  def index
    scope = Current.account.account_users.includes(:user)
    # 部门负责人只看到下属成员；人事与管理层看全部。
    scope = scope.where(user_id: subordinate_user_ids) unless admin_like? || Current.account_user&.crm_hr?
    # active=true 只要在职的：各处「选人」的下拉（考核下发、板块负责人、文档可见范围、
    # 薪酬、绩效设置、公海设置）都该排掉离职的人，否则停用了照样能被选中、被下发。
    # 成员权限页本身不传这个参数——它要显示已停用的人，还有「已停用」筛选页签。
    scope = scope.where(deactivated_at: nil) if params[:active].to_s == 'true'
    @members = scope.order('users.name')
    # crm=true 只要 CRM 成员（管理员 + 有 crm_role 且非人事，口径见 AccountUser#can_access_crm?）。
    # 公海设置的「豁免成员」这类选人场景用：车间、仓管、质检这些岗位从不持有客户，
    # 把他们摆进名单只是让人在四十来个名字里找人更费劲（2026-10-27 用户反馈）。
    # 在 Ruby 里筛而不是 SQL：判定含 module_enabled? 这类非列条件，拆进 SQL 会分叉成两套口径。
    @members = @members.select(&:can_access_crm?) if params[:crm].to_s == 'true'
    @departments_by_user = departments_by_user(@members.map(&:user_id))
  end

  # 每人的部门名（选人弹窗按部门分组用）。一次查完，别在 jbuilder 里逐行查。
  # 一个人可能挂多个部门，主部门（is_primary）排在前面。
  def departments_by_user(user_ids)
    return {} if user_ids.blank?

    Current.account.org_memberships
           .where(user_id: user_ids).includes(:department)
           .order(is_primary: :desc)
           .group_by(&:user_id)
           .transform_values { |ms| ms.filter_map { |m| m.department&.name }.uniq }
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
    error = update_error
    return render json: { error: error[:message] }, status: error[:status] if error

    updates = role_updates
    return render json: { error: '无效的角色' }, status: :unprocessable_entity if updates.nil?

    updates[:module_access] = normalized_modules if params[:member].key?(:module_access)
    # MES 多岗：成员可兼任多个 MES 角色（如仓管+生产）。遗留单值 mes_role 已废弃，不再接受。
    if params[:member].key?(:mes_roles)
      updates[:mes_roles] = Array(params[:member][:mes_roles]).map(&:to_s).reject(&:blank?).uniq
    end
    updates[:erp_role] = params[:member][:erp_role].presence if params[:member].key?(:erp_role)
    if params[:member].key?(:crm_finance)
      updates[:crm_finance] = ActiveModel::Type::Boolean.new.cast(params[:member][:crm_finance])
    end
    # 计入业绩排行：勾了的人即使这个月零成交也留在榜上（见 StatsController#with_zero_owners）。
    if params[:member].key?(:in_sales_rank)
      updates[:in_sales_rank] = ActiveModel::Type::Boolean.new.cast(params[:member][:in_sales_rank])
    end
    if params[:member].key?(:crm_role) || params[:member].key?(:role)
      updates[:org_managed_crm_role] = false
      updates[:org_previous_crm_role] = nil
    end
    @member.update!(updates)
    apply_user_updates
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: friendly_invalid_message(e.record) }, status: :unprocessable_entity
  end

  # 停用（离职）：名下客户/商机按 handover_mode 退回公海或转交，个人文档进回收站，
  # 账号 CRM 角色置无 + 标记停用 + 踢下线并禁止再次登录。可恢复。仅超管/管理员。
  def deactivate
    error = deactivate_error
    return render json: { error: error[:message] }, status: error[:status] if error

    Crm::OffboardingService.new(
      account: Current.account, user_id: @member.user_id, actor: current_user,
      mode: params[:handover_mode].to_s, target_user_id: params[:handover_target_id].presence
    ).perform
    @member.reload
    render :show
  end

  # 恢复：解除停用（可再次登录）。角色/客户不自动还原，由管理员重新分配。
  def reactivate
    return render json: { error: '仅超级管理员或管理员可操作' }, status: :forbidden unless admin_like?

    @member.update!(deactivated_at: nil)
    @member.reload
    render :show
  end

  # 彻底删除：从库里删掉账号，不可恢复。仅用于建错/测试/重复号，且必须已离职（数据已交接）。仅超管/管理员。
  def destroy
    error = destroy_error
    return render json: { error: error[:message] }, status: error[:status] if error

    Crm::MemberDeletionService.new(account: Current.account, account_user: @member).perform
    head :ok
  rescue Crm::MemberDeletionService::NotDeletable => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  rescue_from Crm::OffboardingService::Invalid do |error|
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def destroy_error
    return { message: '仅超级管理员或管理员可删除成员', status: :forbidden } unless admin_like?
    return { message: '不能删除自己', status: :unprocessable_entity } if @member.id == Current.account_user.id
    if @member.administrator? || @member.crm_role == 'deputy_admin'
      return { message: '不能删除超级管理员/管理员账号', status: :forbidden }
    end
    return { message: '请先在成员管理里办理「离职」交接，再彻底删除', status: :unprocessable_entity } if @member.deactivated_at.blank?

    nil
  end

  def deactivate_error
    return { message: '仅超级管理员或管理员可停用成员', status: :forbidden } unless admin_like?
    return { message: '不能停用自己', status: :unprocessable_entity } if @member.id == Current.account_user.id
    if @member.administrator? || @member.crm_role == 'deputy_admin'
      return { message: '不能停用超级管理员/管理员账号', status: :forbidden }
    end

    nil
  end

  def ensure_admin
    return if admin_like? || Current.account_user&.crm_hr? || Current.account_user&.crm_manager?

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

  # 防自锁 → 防提权（管理员/人事各自边界）→ 负责人只可重置下属密码。
  def update_error
    # 仅在改角色时禁止改自己（防自我提权/降权）；改自己的 CRM 英文名等非角色字段允许。
    if @member.id == Current.account_user.id && params[:member].key?(:system_role)
      return { message: '不能修改自己的角色', status: :unprocessable_entity }
    end
    return { message: '仅超级管理员可任免超级管理员', status: :forbidden } if escalation_attempt?
    return { message: '人事不可管理超级管理员/管理员账号', status: :forbidden } if hr_overreach?
    return { message: '部门负责人仅可为下属成员重置密码', status: :forbidden } if manager_overreach?

    nil
  end

  def privileged_actor?
    admin_like? || Current.account_user&.crm_hr?
  end

  # 人事越界：目标是超管/管理员，或试图授予超管/管理员角色。
  def hr_overreach?
    return false unless Current.account_user&.crm_hr?

    @member.administrator? || @member.crm_role == 'deputy_admin' ||
      %w[administrator deputy_admin].include?(params[:member][:system_role].to_s)
  end

  # 部门负责人越界：目标不是下属 / 目标是超管或管理员 / 试图改密码以外的内容。
  def manager_overreach?
    return false if privileged_actor?

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

  # 超级管理员/管理员可直接修改成员账号：姓名、CRM 英文名、登录邮箱、重置密码（改邮箱免二次确认，即时生效）。
  def apply_user_updates
    m = params[:member]
    attrs = {}
    attrs[:name] = m[:name].to_s.strip if m[:name].present?
    attrs[:crm_name] = m[:crm_name].to_s.strip if m.key?(:crm_name)
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
    return { message: '仅超级管理员/管理员/人事可新建成员', status: :forbidden } unless privileged_actor?
    return { message: '仅超级管理员可新建超级管理员', status: :forbidden } if create_escalation_attempt?
    return { message: '人事不可新建超级管理员/管理员', status: :forbidden } if hr_role_grant_attempt?
    return { message: '无效的角色', status: :unprocessable_entity } if SYSTEM_ROLE_MAP[params[:member][:system_role].to_s].nil?
    return { message: '该邮箱已注册', status: :unprocessable_entity } if User.exists?(email: direct_email)

    nil
  end

  def hr_role_grant_attempt?
    Current.account_user&.crm_hr? && %w[administrator deputy_admin].include?(params[:member][:system_role].to_s)
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
