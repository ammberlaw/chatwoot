# 员工薪资配置（HR·KPI 一期，仅管理员可读写——薪资敏感）。对应 A-CRM(Twenty) employeeComp。
# 绩效基数 = 月薪总额 × 绩效占比%；业绩项建议分 = 实际销售额 ÷ 月度业绩底线目标 × 权重。
# performance_ratio 每人独立（默认 10%），owner 指向业务员(User)。
# == Schema Information
#
# Table name: crm_employee_comps
#
#  id                     :bigint           not null, primary key
#  baseline_target_micros :bigint
#  monthly_salary_micros  :bigint
#  name                   :string           not null
#  performance_ratio      :integer          default(10)
#  rank_note              :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  owner_id               :bigint
#
# Indexes
#
#  index_crm_employee_comps_on_account_id  (account_id)
#  index_crm_employee_comps_on_owner_id    (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::EmployeeComp < ApplicationRecord
  # 薪资敏感：变更全程审计（查看日志见 Crm::AccessLog）。
  audited

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true

  validates :name, presence: true

  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
end
