# 岗位权限模板：一个岗位打包好「系统角色 + 可进系统模块 + MES 岗位 + 财务权限」，
# 管理员在成员权限页一键套用给某个成员。模板本身可增删改（不写死在代码里）。
# == Schema Information
#
# Table name: crm_role_templates
#
#  id            :bigint           not null, primary key
#  crm_finance   :boolean          default(FALSE), not null
#  mes_roles     :string           default([]), not null, is an Array
#  module_access :string           default([]), not null, is an Array
#  name          :string           not null
#  position      :integer          default(0), not null
#  system_role   :string           default(""), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_crm_role_templates_on_account_and_name      (account_id,name) UNIQUE
#  index_crm_role_templates_on_account_and_position  (account_id,position)
#
class Crm::RoleTemplate < ApplicationRecord
  belongs_to :account

  # 系统角色取值与成员控制器 SYSTEM_ROLE_MAP 对齐（空串=无角色/不进 CRM）。
  SYSTEM_ROLES = ['', 'administrator', 'deputy_admin', 'manager', 'sales', 'hr'].freeze

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :system_role, inclusion: { in: SYSTEM_ROLES }
  validate :modules_and_mes_valid

  before_save :normalize_arrays

  scope :ordered, -> { order(:position, :id) }

  # 首次进入时播种的常用岗位（管理员之后可任意改名/改权限/删除）。
  DEFAULTS = [
    { name: '外贸业务员', system_role: 'sales', module_access: %w[crm], mes_roles: [], crm_finance: false },
    { name: '业务负责人', system_role: 'manager', module_access: %w[crm], mes_roles: [], crm_finance: false },
    { name: '管理员', system_role: 'deputy_admin', module_access: %w[crm mes], mes_roles: [], crm_finance: false },
    { name: '人事', system_role: 'hr', module_access: %w[crm], mes_roles: [], crm_finance: false },
    { name: '财务', system_role: 'sales', module_access: %w[crm], mes_roles: [], crm_finance: true },
    { name: '仓库管理', system_role: '', module_access: %w[mes], mes_roles: %w[warehouse], crm_finance: false },
    { name: '生产/车间', system_role: '', module_access: %w[mes], mes_roles: %w[production], crm_finance: false },
    { name: '采购', system_role: '', module_access: %w[mes], mes_roles: %w[buyer], crm_finance: false },
    { name: '计划 PMC', system_role: '', module_access: %w[mes], mes_roles: %w[pmc], crm_finance: false },
    { name: '工程', system_role: '', module_access: %w[mes], mes_roles: %w[engineer], crm_finance: false }
  ].freeze

  # 账号还没有任何模板时，播种一套常用岗位当起点。已有则不动。
  def self.seed_defaults!(account)
    return if account.crm_role_templates.exists?

    DEFAULTS.each_with_index do |attrs, index|
      account.crm_role_templates.create!(attrs.merge(position: index))
    end
  end

  private

  def normalize_arrays
    self.module_access = Array(module_access).map(&:to_s).uniq & AccountUser::MODULES
    self.mes_roles = Array(mes_roles).map(&:to_s).uniq & AccountUser::MES_ROLES
  end

  def modules_and_mes_valid
    bad_mod = Array(module_access).map(&:to_s) - AccountUser::MODULES
    errors.add(:module_access, "含非法模块：#{bad_mod.join(',')}") if bad_mod.any?
    bad_mes = Array(mes_roles).map(&:to_s) - AccountUser::MES_ROLES
    errors.add(:mes_roles, "含非法 MES 岗位：#{bad_mes.join(',')}") if bad_mes.any?
  end
end
