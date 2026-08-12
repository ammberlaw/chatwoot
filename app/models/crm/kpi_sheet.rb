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
#  paid_at                 :datetime
#  pass_score              :integer
#  payout_coefficient      :decimal(6, 3)
#  payout_note             :text
#  performance_base_micros :bigint
#  performance_ratio       :integer
#  period_month            :datetime         not null
#  remark                  :text
#  result_note             :text
#  return_reason           :text
#  returned_at             :datetime
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
#  paid_by_id              :bigint
#  returned_by_id          :bigint
#
# Indexes
#
#  index_crm_kpi_sheets_on_account_id                      (account_id)
#  index_crm_kpi_sheets_on_account_id_and_period_month     (account_id,period_month)
#  index_crm_kpi_sheets_on_crm_kpi_scheme_id               (crm_kpi_scheme_id)
#  index_crm_kpi_sheets_on_crm_kpi_scheme_id_and_owner_id  (crm_kpi_scheme_id,owner_id)
#  index_crm_kpi_sheets_on_owner_id                        (owner_id)
#  index_crm_kpi_sheets_on_returned_by_id                  (returned_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_kpi_scheme_id => crm_kpi_schemes.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id) ON DELETE => nullify
#  fk_rails_...  (returned_by_id => users.id) ON DELETE => nullify
#
class Crm::KpiSheet < ApplicationRecord
  STATUSES = %w[PENDING SUBMITTED SCORED HR_CONFIRMED ARCHIVED].freeze

  belongs_to :account
  belongs_to :scheme, class_name: 'Crm::KpiScheme', foreign_key: :crm_kpi_scheme_id, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true
  belongs_to :hr, class_name: 'User', optional: true
  belongs_to :gm, class_name: 'User', optional: true
  belongs_to :returned_by, class_name: 'User', optional: true
  belongs_to :paid_by, class_name: 'User', optional: true

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
  # 试用期员工只算考核得分、不发绩效薪资：基数/系数/实发一律清空。
  def recompute_payout!
    self.total_score = sheet_items.sum { |i| i.score || 0 }
    return clear_payout! if probation?

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

  # 考核月是否处于试用期：按被考核人的员工档案（转正日期/入职+试用月数/状态）自动判断。
  # 无关联档案时按「非试用」处理，绩效照常核算。
  def probation?
    return false unless owner_id

    account.crm_employees.find_by(user_id: owner_id)&.probation_in?(period_month) || false
  end

  # 退回重填：回到 PENDING，记录退回原因/人/时间，并清空后续所有签名与核算，
  # 让员工改完从头重走审批链。完成值/得分保留（供在原值上修改，非从零填）。
  def reset_for_return!(reason:, by:)
    assign_attributes(
      status: 'PENDING', return_reason: reason, returned_at: Time.current, returned_by_id: by.id,
      employee_signed_at: nil, manager_id: nil, manager_signed_at: nil,
      hr_id: nil, hr_confirmed_at: nil, gm_id: nil, gm_confirmed_at: nil,
      total_score: nil, payout_coefficient: nil, actual_payout_micros: nil
    )
    [employee_signature, manager_signature, hr_signature, gm_signature].each { |sig| sig.purge if sig.attached? }
    save!
  end

  # 退回主管改分：SCORED 或 HR_CONFIRMED（待总经理确认）回到 SUBMITTED（待打分）。
  # 清主管签名/核算，并清掉人事确认与签名（分数改了须人事重新确认）；
  # 员工填报、员工签名、各项已打分数一律保留（供主管在原分上改错的那项即可）。
  def reopen_scoring!(reason:, by:)
    assign_attributes(
      status: 'SUBMITTED', return_reason: reason.presence, returned_at: Time.current, returned_by_id: by.id,
      manager_id: nil, manager_signed_at: nil,
      hr_id: nil, hr_confirmed_at: nil,
      # 从已归档退回时也要清掉总经理确认与签名，避免残留归档痕迹（非归档场景这些本就是 nil，无副作用）。
      gm_id: nil, gm_confirmed_at: nil,
      total_score: nil, payout_coefficient: nil, actual_payout_micros: nil
    )
    [manager_signature, hr_signature, gm_signature].each { |sig| sig.purge if sig.attached? }
    save!
  end

  # 财务发放：仅归档(ARCHIVED)表可标记「已发放」，金额用系统已算的 actual_payout_micros。
  def mark_paid!(by:)
    update!(paid_at: Time.current, paid_by_id: by.id)
  end

  # 撤销发放（财务/管理员点错兜底）。
  def unmark_paid!
    update!(paid_at: nil, paid_by_id: nil)
  end

  private

  # 试用期：清空绩效基数/系数/实发（考核得分保留）。
  def clear_payout!
    self.performance_base_micros = nil
    self.payout_coefficient = nil
    self.actual_payout_micros = nil
    save!
  end

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
