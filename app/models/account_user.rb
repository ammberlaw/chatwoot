# == Schema Information
#
# Table name: account_users
#
#  id                       :bigint           not null, primary key
#  active_at                :datetime
#  auto_offline             :boolean          default(TRUE), not null
#  availability             :integer          default("online"), not null
#  crm_finance              :boolean          default(FALSE), not null
#  crm_role                 :string
#  deactivated_at           :datetime
#  erp_role                 :string
#  mes_role                 :string
#  mes_roles                :string           default([]), not null, is an Array
#  module_access            :text             default(["crm", "erp", "mes"]), not null, is an Array
#  role                     :integer          default("agent")
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint
#  agent_capacity_policy_id :bigint
#  crm_team_id              :bigint
#  custom_role_id           :bigint
#  inviter_id               :bigint
#  tiktok_department_id     :bigint
#  user_id                  :bigint
#
# Indexes
#
#  index_account_users_on_account_id                (account_id)
#  index_account_users_on_account_id_and_crm_role   (account_id,crm_role)
#  index_account_users_on_account_id_and_erp_role   (account_id,erp_role)
#  index_account_users_on_agent_capacity_policy_id  (agent_capacity_policy_id)
#  index_account_users_on_crm_team_id               (crm_team_id)
#  index_account_users_on_custom_role_id            (custom_role_id)
#  index_account_users_on_mes_roles                 (mes_roles) USING gin
#  index_account_users_on_tiktok_department_id      (tiktok_department_id)
#  index_account_users_on_user_id                   (user_id)
#  uniq_user_id_per_account_id                      (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (crm_team_id => crm_teams.id) ON DELETE => nullify
#  fk_rails_...  (tiktok_department_id => tiktok_departments.id) ON DELETE => nullify
#

class AccountUser < ApplicationRecord
  include AvailabilityStatusable

  belongs_to :account
  belongs_to :user
  belongs_to :inviter, class_name: 'User', optional: true
  belongs_to :crm_team, class_name: 'Crm::Team', optional: true, inverse_of: :account_users
  belongs_to :tiktok_department, class_name: 'Tiktok::Department', optional: true, inverse_of: :account_users

  enum role: { agent: 0, administrator: 1 }
  enum availability: { online: 0, offline: 1, busy: 2 }

  # CRM 条线角色（与 Chatwoot role 正交）：副管理员 / 部门负责人 / 业务员；空=非 CRM 人员。
  CRM_ROLES = %w[deputy_admin manager sales hr].freeze
  validates :crm_role, inclusion: { in: CRM_ROLES }, allow_nil: true

  # MES 条线角色：PMC(计划) / 工程 / 采购 / 仓管 / 生产(车间)；空=只读可见，不可写。
  # 多值——支持同模块兼岗（如 PMC 同时负责采购）；能力取各角色并集。
  MES_ROLES = %w[pmc engineer buyer warehouse production].freeze
  validate :mes_roles_valid

  def mes_roles_valid
    invalid = mes_roles.to_a - MES_ROLES
    errors.add(:mes_roles, "含非法角色：#{invalid.join(',')}") if invalid.any?
  end

  # 角色 → 可写能力域。管理员/副管理员全能力。
  # product = 产品档案/编码（仅工程与 PMC 可增删改；采购管供应商/物料走 master，不含产品）。
  MES_CAPABILITIES = {
    'pmc' => %w[order bom master product],
    'engineer' => %w[bom master product],
    'buyer' => %w[purchase master],
    'warehouse' => %w[stock shipment quality],
    'production' => %w[report quality]
  }.freeze

  # 能否在 MES 某能力域写操作（下单/BOM/采购/库存/报工/出库/主数据/产品档案）。
  # 多角色取并集：任一角色具备该能力即可。
  def mes_can?(capability)
    return true if administrator? || crm_deputy_admin?

    mes_capability_list.include?(capability.to_s)
  end

  # 该成员的有效 MES 角色：多值 mes_roles 优先，兼容基线单值 mes_role（成员页仍单值下拉）。
  def effective_mes_roles
    (mes_roles.to_a + [mes_role]).reject(&:blank?).uniq
  end

  # MES 操作岗（有任一 MES 角色）或管理员/副管理员。供应商/采购单含采购价与供应商资料，
  # 纯 CRM 业务角色（销售端）不可读——生态硬约束：销售端绝不可见成本/供应商。
  def mes_staff?
    administrator? || crm_deputy_admin? || effective_mes_roles.any?
  end

  # 前端用：该成员可写的 MES 能力域列表（管理员/副管理员全给；多角色取并集）。
  def mes_capability_list
    return MES_CAPABILITIES.values.flatten.uniq if administrator? || crm_deputy_admin?

    effective_mes_roles.flat_map { |r| MES_CAPABILITIES.fetch(r, []) }.uniq
  end

  # ERP（财务管理）条线角色：finance(财务，全域) / cashier(出纳，预留，仅收付+资金)。
  # 空=无 ERP 权限。单值——财务条线一档即可，与 MES 多岗不同。
  # ⚠️ 生态硬约束：ERP 承载成本/供应商/毛利，纯销售角色绝不可进（见 can_access_erp?）。
  ERP_ROLES = %w[finance cashier].freeze
  validates :erp_role, inclusion: { in: ERP_ROLES }, allow_nil: true

  # 角色 → 可写能力域。管理员/副管理员全能力。
  ERP_CAPABILITIES = {
    'finance' => %w[receivable payable payment cash cost ledger voucher report close asset doc claim supplier],
    'cashier' => %w[payment cash]
  }.freeze

  # 能否在 ERP 某能力域写操作（应收/应付/收付/资金/成本/账簿/凭证/报表/结账/资产/单证/报销/供应商）。
  def erp_can?(capability)
    return true if administrator? || crm_deputy_admin?

    erp_capability_list.include?(capability.to_s)
  end

  # 前端用：该成员可写的 ERP 能力域列表（管理员/副管理员全给）。
  def erp_capability_list
    return ERP_CAPABILITIES.values.flatten.uniq if administrator? || crm_deputy_admin?
    return [] if erp_role.blank?

    ERP_CAPABILITIES.fetch(erp_role, [])
  end

  # ERP 操作岗（有 erp_role）或管理员/副管理员。
  def erp_staff?
    administrator? || crm_deputy_admin? || erp_role.present?
  end

  # 能否进入 ERP：管理员/副管理员自动可入；否则需被赋予 erp_role 且 ERP 模块开关打开。
  # 销售端（仅 crm_role、无 erp_role）一律不可入——成本/供应商/毛利硬隔离。
  def can_access_erp?
    administrator? || crm_deputy_admin? || (erp_role.present? && module_enabled?('erp'))
  end

  # 业务系统模块使用权限（成员权限页按人开关）；管理员始终全模块。
  MODULES = %w[crm erp mes].freeze

  accepts_nested_attributes_for :account

  after_create_commit :notify_creation, :create_notification_setting
  after_destroy :notify_deletion, :remove_user_from_account, :discard_personal_crm_docs
  after_save :update_presence_in_redis, if: :saved_change_to_availability?

  validates :user_id, uniqueness: { scope: :account_id }

  # 离职/停用：deactivated_at 有值＝已停用（禁止登录、退出各业务系统）；空＝在职。可恢复。
  scope :active_members, -> { where(deactivated_at: nil) }

  def deactivated?
    deactivated_at.present?
  end

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

  # 能否进入 TikTok 板块：管理员/副管理员/财务，或任一 TK 部门的负责人/成员。
  def can_access_tiktok?
    Tiktok::AccessScope.new(account, self).can_access?
  end

  # 能否查看 TikTok 利润表（含成本/毛利/净利）：管理层/财务，或 TK 部门负责人；普通成员不可见。
  def can_view_tiktok_profit?
    Tiktok::AccessScope.new(account, self).can_view_profit?
  end

  # 财务身份（与业务员身份叠加）：可查看全员「已通过」提成表并导出。管理员天然具备。
  def crm_finance?
    administrator? || self[:crm_finance]
  end

  # CRM 数据条线是否主管（部门负责人）：看本部门（含下级）；业务员/其他看自己。
  # 支持身份叠加：副管理员/管理员兼任业务部门负责人时同时具备主管身份。
  # 数据范围不受影响——所有调用方都先判管理员/副管理员（更大范围）再判主管。
  def crm_manager?
    crm_role == 'manager' || leads_business_department?
  end

  # 是否任一部门的负责人（组织架构事实，与角色字段无关）。
  # 不限业务条线：设计/TK/外贸等部门命名不含「销售/业务」，按条线判会漏；
  # 数据范围始终只算所辖部门子树，非业务部门负责人也需要考核打分/考勤汇总。
  def leads_business_department?
    return @leads_business_department if defined?(@leads_business_department)

    @leads_business_department = account.org_departments.where(leader_id: user_id).exists?
  end

  # 是否任一 CRM 团队的负责人（crm_teams.team_lead_id）。销售订单/邮件等按 CRM 团队收口时用；
  # 与部门负责人相互独立——CRM 团队负责人不一定是组织部门负责人。
  def crm_team_lead?
    return @crm_team_lead if defined?(@crm_team_lead)

    @crm_team_lead = account.crm_teams.where(team_lead_id: user_id).exists?
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
