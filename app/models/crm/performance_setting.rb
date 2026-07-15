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

  # 考核方案对该成员是否可见（管理员始终可见；无记录时默认可见）。
  def self.scheme_visible?(setting, account_user)
    return true if account_user.administrator?

    if account_user.crm_manager?
      setting.nil? || setting.scheme_visible_manager
    elsif account_user.crm_role.present?
      setting.nil? || setting.scheme_visible_sales
    else
      false
    end
  end

  # 考核表对该成员是否可见（管理员/被指定人事/总经理始终可见——审批需要）。
  def self.sheet_visible?(setting, account_user)
    return true if account_user.administrator?
    return true if setting && [setting.hr_owner_id, setting.gm_owner_id].include?(account_user.user_id)

    if account_user.crm_manager?
      setting.nil? || setting.sheet_visible_manager
    elsif account_user.crm_role.present?
      setting.nil? || setting.sheet_visible_sales
    else
      false
    end
  end
end
