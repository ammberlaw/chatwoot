# 月度绩效考核方案（HR·KPI 一期）。对应 A-CRM(Twenty) kpiScheme。
# 一月一份、可编辑：及格分、单项计分上限、发放说明、状态（草稿→已下发）。
# 下含考核指标(scheme_items)与发放系数档(payout_tiers)，随方案级联删除。
# == Schema Information
#
# Table name: crm_kpi_schemes
#
#  id                 :bigint           not null, primary key
#  item_score_cap_pct :integer          default(120)
#  name               :string           not null
#  pass_score         :integer          default(70)
#  payout_note        :text
#  result_note        :text
#  detail_tables      :jsonb            not null
#  scheme_month       :datetime         not null
#  status             :string           default("DRAFT"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#
# Indexes
#
#  index_crm_kpi_schemes_on_account_id                   (account_id)
#  index_crm_kpi_schemes_on_account_id_and_scheme_month  (account_id,scheme_month)
#  index_crm_kpi_schemes_on_created_by_id                (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Crm::KpiScheme < ApplicationRecord
  STATUSES = %w[DRAFT PUBLISHED].freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :scheme_items, class_name: 'Crm::SchemeItem', foreign_key: :crm_kpi_scheme_id, dependent: :destroy, inverse_of: :scheme
  has_many :payout_tiers, class_name: 'Crm::PayoutTier', foreign_key: :crm_kpi_scheme_id, dependent: :destroy, inverse_of: :scheme

  accepts_nested_attributes_for :scheme_items, allow_destroy: true
  accepts_nested_attributes_for :payout_tiers, allow_destroy: true

  validates :name, presence: true
  validates :scheme_month, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_month, ->(date) { where(scheme_month: date.beginning_of_month..date.end_of_month) }

  before_validation :normalize_scheme_month

  private

  def normalize_scheme_month
    self.scheme_month = scheme_month&.beginning_of_month
  end
end
