# 销售团队（组长带组）。对应 A-CRM(Twenty) team（CRM_SPEC §12.1）。
# 业务员经 account_users.crm_team_id 归属团队；订单按 owner 自动反写所属团队。
# == Schema Information
#
# Table name: crm_teams
#
#  id           :bigint           not null, primary key
#  description  :text
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  team_lead_id :bigint
#
# Indexes
#
#  index_crm_teams_on_account_id    (account_id)
#  index_crm_teams_on_team_lead_id  (team_lead_id)
#
# Foreign Keys
#
#  fk_rails_...  (team_lead_id => users.id) ON DELETE => nullify
#
class Crm::Team < ApplicationRecord
  belongs_to :account
  belongs_to :team_lead, class_name: 'User', optional: true
  has_many :account_users, foreign_key: :crm_team_id, dependent: :nullify, inverse_of: :crm_team
  has_many :members, through: :account_users, source: :user
  # 在职成员：离职的人停用后 crm_team_id 还挂着（保留历史归属，便于恢复），
  # 但花名册、下拉、@提及都不该再出现他——停用只拦登录是不够的。
  has_many :active_account_users,
           -> { active_members },
           class_name: 'AccountUser',
           foreign_key: :crm_team_id,
           inverse_of: :crm_team,
           dependent: nil
  has_many :active_members, through: :active_account_users, source: :user
  has_many :sales_orders, class_name: 'Crm::SalesOrder', foreign_key: :crm_team_id, dependent: :nullify, inverse_of: :crm_team

  validates :name, presence: true, uniqueness: { scope: :account_id }
end
