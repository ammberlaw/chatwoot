# 发放系数档（考核方案的子项，可编辑）。对应 A-CRM(Twenty) payoutTier。
# 把总分区间映射到绩效发放系数：实发绩效 = 绩效基数 × 系数。
# proportional=true 时该档系数取「得分/100」（满分溢出档），coefficient 作为上限。
# == Schema Information
#
# Table name: crm_payout_tiers
#
#  id                :bigint           not null, primary key
#  coefficient       :decimal(6, 3)
#  max_score         :integer
#  min_score         :integer
#  name              :string           not null
#  proportional      :boolean          default(FALSE)
#  sort_order        :integer          default(0)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_kpi_scheme_id :bigint           not null
#
# Indexes
#
#  index_crm_payout_tiers_on_account_id         (account_id)
#  index_crm_payout_tiers_on_crm_kpi_scheme_id  (crm_kpi_scheme_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_kpi_scheme_id => crm_kpi_schemes.id) ON DELETE => cascade
#
class Crm::PayoutTier < ApplicationRecord
  belongs_to :account
  belongs_to :scheme, class_name: 'Crm::KpiScheme', foreign_key: :crm_kpi_scheme_id, inverse_of: :payout_tiers

  validates :name, presence: true

  # 经方案嵌套创建时自动继承 account。
  before_validation { self.account_id ||= scheme&.account_id }

  scope :ordered, -> { order(:sort_order, :id) }
end
