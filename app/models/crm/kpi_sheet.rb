# 个人考核表（HR·KPI 二期）：下发方案给某员工后生成，走 5 状态审批链。
# 流程：员工填报完成值+签(SUBMITTED) → 主管打分+签(SCORED) → 人事确认+签(HR_CONFIRMED)
#       → 总经理确认+签(ARCHIVED)。4 方电子签走 ActiveStorage。
# 绩效核算：绩效基数 = 月薪 × 绩效占比%；实发 = 基数 × 发放系数（按总分匹配发放档）。
# == Schema Information
#
# Table name: crm_kpi_sheets
#
#  id                      :bigint           not null, primary key
#  actual_payout_micros    :bigint
#  baseline_target_micros  :bigint
#  employee_signed_at      :datetime
#  gm_confirmed_at         :datetime
#  hr_confirmed_at         :datetime
#  item_score_cap_pct      :integer
#  manager_signed_at       :datetime
#  monthly_salary_micros   :bigint
#  pass_score              :integer
#  payout_coefficient      :decimal(6, 3)
#  performance_base_micros :bigint
#  performance_ratio       :integer
#  period_month            :datetime         not null
#  scheme_name             :string
#  status                  :string           default("PENDING"), not null
#  total_score             :decimal(7, 2)
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  crm_kpi_scheme_id       :bigint
#  gm_id                   :bigint
#  hr_id                   :bigint
#  manager_id              :bigint
#  owner_id                :bigint
#
# Indexes
#
#  index_crm_kpi_sheets_on_account_id                      (account_id)
#  index_crm_kpi_sheets_on_account_id_and_period_month     (account_id,period_month)
#  index_crm_kpi_sheets_on_crm_kpi_scheme_id               (crm_kpi_scheme_id)
#  index_crm_kpi_sheets_on_crm_kpi_scheme_id_and_owner_id  (crm_kpi_scheme_id,owner_id)
#  index_crm_kpi_sheets_on_owner_id                        (owner_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_kpi_scheme_id => crm_kpi_schemes.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#
class Crm::KpiSheet < ApplicationRecord
  STATUSES = %w[PENDING SUBMITTED SCORED HR_CONFIRMED ARCHIVED].freeze

  belongs_to :account
  belongs_to :scheme, class_name: 'Crm::KpiScheme', foreign_key: :crm_kpi_scheme_id, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true
  belongs_to :hr, class_name: 'User', optional: true
  belongs_to :gm, class_name: 'User', optional: true

  has_many :sheet_items, class_name: 'Crm::KpiSheetItem', foreign_key: :crm_kpi_sheet_id, dependent: :destroy, inverse_of: :sheet

  has_one_attached :employee_signature
  has_one_attached :manager_signature
  has_one_attached :hr_signature
  has_one_attached :gm_signature

  validates :period_month, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_month, ->(date) { where(period_month: date.beginning_of_month..date.end_of_month) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }

  # 重算总分与绩效发放（打分后调用）。金额整数微分，系数保留 3 位。
  def recompute_payout!
    self.total_score = sheet_items.sum { |i| i.score || 0 }
    base = ((monthly_salary_micros || 0) * (performance_ratio || 0)) / 100
    self.performance_base_micros = base
    tier = matched_tier
    if tier
      coef = tier.proportional ? [total_score.to_f / 100, tier.coefficient.to_f].min : tier.coefficient.to_f
      self.payout_coefficient = coef
      self.actual_payout_micros = (base * coef).round
    else
      self.payout_coefficient = nil
      self.actual_payout_micros = nil
    end
    save!
  end

  private

  # 按总分匹配发放档（含起不含止靠 min/max；max 为空表示开区间）。
  def matched_tier
    return nil unless scheme

    scheme.payout_tiers.detect do |t|
      lo = t.min_score || 0
      hi = t.max_score
      total_score >= lo && (hi.nil? || total_score <= hi)
    end
  end
end
