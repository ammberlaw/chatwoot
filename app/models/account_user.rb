# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  crm_role                 :string
#  mes_role                 :string
#  module_access            :text             default(["crm", "erp", "mes"]), not null, is an Array
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  crm_team_id              :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_account_id_and_crm_role   (account_id,crm_role)
#  index_account_users_on_account_id_and_mes_role   (account_id,mes_role)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_crm_team_id               (crm_team_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (crm_team_id => crm_teams.id) ON DELETE => nullify
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :crm_team, class_name: 'Crm::Team', optional: true, inverse_of: :account_users

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  # CRM 条线角色（与 Chatwoot role 正交）：副管理员 / 部门负责人 / 业务员；空=非 CRM 人员。
  CRM_ROLES = %w[deputy_admin manager sales hr].freeze
  validates :crm_role, inclusion: { in: CRM_ROLES }, allow_nil: true

  # MES 条线角色：PMC(计划) / 工程 / 采购 / 仓管 / 生产(车间)；空=只读可见，不可写。
  MES_ROLES = %w[pmc engineer buyer warehouse production].freeze
  validates :mes_role, inclusion: { in: MES_ROLES }, allow_nil: true

  # 角色 → 可写能力域。管理员/副管理员全能力。
  MES_CAPABILITIES = {
    'pmc' => %w[order master],
    'engineer' => %w[bom master],
    'buyer' => %w[purchase master],
    'warehouse' => %w[stock shipment quality],
    'production' => %w[report quality]
  }.freeze

  # 能否在 MES 某能力域写操作（下单/BOM/采购/库存/报工/出库/主数据）。
  def mes_can?(capability)
    return true if administrator? || crm_deputy_admin?

    MES_CAPABILITIES.fetch(mes_role.to_s, []).include?(capability.to_s)
  end

  # 前端用：该成员可写的 MES 能力域列表（管理员/副管理员全给）。
  def mes_capability_list
    return MES_CAPABILITIES.values.flatten.uniq if administrator? || crm_deputy_admin?

    MES_CAPABILITIES.fetch(mes_role.to_s, [])
  end

  # 业务系统模块使用权限（成员权限页按人开关）；管理员始终全模块。
  MODULES = %w[crm erp mes].freeze

  accepts_nested_attributes_for :account

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account, :discard_personal_crm_docs
  after_save :update_presence_in_redis, if: :saved_change_to_availability?

  validates :user_id, uniqueness: { scope: :account_id }

  # 模块使用权限：管理员始终全模块；其他人按成员权限页的开关。
  def module_enabled?(mod)
    administrator? || module_access.include?(mod)
  end

  # 能否进入 CRM：系统管理员自动可入；否则需被赋予角色且 CRM 模块开关打开。
  def can_access_crm?
    # 人事角色不进入 CRM 销售数据，只用 HR/共享模块。
    administrator? || (crm_role.present? && crm_role != 'hr' && module_enabled?('crm'))
  end

  def crm_hr?
    crm_role == 'hr'
  end

  # CRM 数据条线是否主管（部门负责人）：看本部门（含下级）；业务员/其他看自己。
  def crm_manager?
    crm_role == 'manager'
  end

  # 副管理员：CRM 内数据范围与文档管理同管理员；账号级管理（成员权限/回收站等）仍仅系统管理员。
  def crm_deputy_admin?
    crm_role == 'deputy_admin'
  end

  # 密码自助权限：2026-07-17 起放开为全员可自改密码（个人资料 + 忘记密码邮件）。
  # 如需恢复集中管控，把返回值改回 administrator? || crm_deputy_admin? || oa_template_maintainer? 即可。
  def password_self_service?
    true
  end

  # 组织架构维护权：超级管理员/管理员，或人事部门成员（部门名含「人事」，含其下级部门）。
  def org_maintainer?
    return true if administrator? || crm_deputy_admin? || crm_hr?

    member_of_department_named?('人事')
  end

  # OA 审批模板维护权：超级管理员/管理员，或人事部门成员（部门名含「人事」，含其下级部门）。
  def oa_template_maintainer?
    return true if administrator? || crm_deputy_admin? || crm_hr?

    member_of_department_named?('人事')
  end

  # 是否属于名称含指定关键词的部门（含其下级部门）。
  def member_of_department_named?(keyword)
    root_ids = account.org_departments.where('name LIKE ?', "%#{keyword}%").pluck(:id)
    return false if root_ids.empty?

    dept_ids = Org::Department.subtree_ids(account, root_ids)
    account.org_memberships.exists?(user_id: user_id, department_id: dept_ids)
  end

  def create_notification_setting
    setting = user.notification_settings.new(account_id: account.id)
    setting.selected_email_flags = [:email_conversation_assignment]
    setting.selected_push_flags = [:push_conversation_assignment]
    setting.save!
  end

  def remove_user_from_account
    ::Agents::DestroyJob.perform_later(account, user)
  end

  # 成员被移除（离职删号）后，其个人文档自动进入文档回收站，避免变成谁也看不到的孤儿数据。
  def discard_personal_crm_docs
    account.crm_knowledge_docs.kept.where(scope: 'PERSONAL', owner_id: user_id).find_each do |doc|
      doc.discard!(user_id)
    end
  end

  def permissions
    administrator? ? ['administrator'] : ['agent']
  end

  def push_event_data
    {
      id: id,
      availability: availability,
      role: role,
      user_id: user_id
    }
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(AGENT_ADDED, Time.zone.now, account: account)
  end

  def notify_deletion
    Rails.configuration.dispatcher.dispatch(AGENT_REMOVED, Time.zone.now, account: account)
  end

  def update_presence_in_redis
    OnlineStatusTracker.set_status(account.id, user.id, availability)
  end
end

AccountUser.prepend_mod_with('AccountUser')
AccountUser.include_mod_with('Audit::AccountUser')
AccountUser.include_mod_with('Concerns::AccountUser')
