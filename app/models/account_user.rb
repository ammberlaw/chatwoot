# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  crm_role                 :string
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
  CRM_ROLES = %w[deputy_admin manager sales].freeze
  validates :crm_role, inclusion: { in: CRM_ROLES }, allow_nil: true

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
    administrator? || (crm_role.present? && module_enabled?('crm'))
  end

  # CRM 数据条线是否主管（部门负责人）：看本部门（含下级）；业务员/其他看自己。
  def crm_manager?
    crm_role == 'manager'
  end

  # 副管理员：CRM 内数据范围与文档管理同管理员；账号级管理（成员权限/回收站等）仍仅系统管理员。
  def crm_deputy_admin?
    crm_role == 'deputy_admin'
  end

  # 密码自助权限：超级管理员/管理员/行政部门成员可自改密码；其他成员的密码由管理员统一重置。
  def password_self_service?
    administrator? || crm_deputy_admin? || oa_template_maintainer?
  end

  # OA 审批模板维护权：超级管理员/管理员，或行政部门成员（部门名含「行政」，含其下级部门）。
  def oa_template_maintainer?
    return true if administrator? || crm_deputy_admin?

    root_ids = account.org_departments.where('name LIKE ?', '%行政%').pluck(:id)
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
