# 绩效审批人设置（单记录/账号）：指定人事、总经理是谁（决定谁能点人事/总经理确认）。
# == Schema Information
#
# Table name: crm_performance_settings
#
#  id                     :bigint           not null, primary key
#  scheme_visible_manager :boolean          default(TRUE), not null
#  scheme_visible_sales   :boolean          default(TRUE), not null
#  sheet_visible_manager  :boolean          default(TRUE), not null
#  sheet_visible_sales    :boolean          default(TRUE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  gm_owner_id            :bigint
#  hr_owner_id            :bigint
#
# Indexes
#
#  index_crm_performance_settings_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (gm_owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (hr_owner_id => users.id) ON DELETE => nullify
#
class Crm::PerformanceSetting < ApplicationRecord
  belongs_to :account
  belongs_to :hr_owner, class_name: 'User', optional: true
  belongs_to :gm_owner, class_name: 'User', optional: true

  # 单记录：取或建。
  def self.for_account(account)
    account.crm_performance_setting || account.create_crm_performance_setting!
  end

  # 管理员/副管理员对绩效配置始终全可见。
  def self.admin_like?(account_user)
    account_user.administrator? || account_user.crm_deputy_admin?
  end

  # 按 CRM 角色查对应可见性开关（无记录时默认可见；无 CRM 角色不可见）。
  def self.role_visible?(setting, account_user, manager_flag, sales_flag)
    if account_user.crm_manager?
      setting.nil? || setting.public_send(manager_flag)
    elsif account_user.crm_role.present?
      setting.nil? || setting.public_send(sales_flag)
    else
      false
    end
  end

  # 考核方案仅 超管/管理员/人事部门成员/指定人事/总经理/部门负责人 可见；
  # 业务员与普通成员一律不可见（2026-07-17 收口，scheme_visible_sales 开关废弃）。
  def self.scheme_visible?(setting, account_user)
    return true if admin_like?(account_user)
    return true if account_user.crm_hr? || account_user.member_of_department_named?('人事')
    return true if setting && [setting.hr_owner_id, setting.gm_owner_id].include?(account_user.user_id)

    account_user.crm_manager? && (setting.nil? || setting.scheme_visible_manager)
  end

  # 考核表对该成员是否可见（管理员/副管理员/被指定人事/总经理始终可见——审批需要）。
  def self.sheet_visible?(setting, account_user)
    return true if admin_like?(account_user) || account_user.crm_hr?
    return true if setting && [setting.hr_owner_id, setting.gm_owner_id].include?(account_user.user_id)

    role_visible?(setting, account_user, :sheet_visible_manager, :sheet_visible_sales)
  end
end
