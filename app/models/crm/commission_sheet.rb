# 提成表主单：业务员按月填报订单明细，交主管审批，通过后财务查看/导出算提成。
# 系统只负责收集 + 流转 + 导出，不在系统内计算提成金额（财务线下按比例算）。
# 流程：草稿(DRAFT) → 提交(SUBMITTED) → 主管通过(APPROVED) / 退回(RETURNED，回到草稿态可改)。
# == Schema Information
#
# Table name: crm_commission_sheets
#
#  id             :bigint           not null, primary key
#  approved_at    :datetime
#  period_month   :datetime         not null
#  remark         :text
#  return_reason  :text
#  returned_at    :datetime
#  status         :string           default("DRAFT"), not null
#  submitted_at   :datetime
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  manager_id     :bigint
#  owner_id       :bigint
#  returned_by_id :bigint
#
# Indexes
#
#  index_crm_commission_sheets_on_account_id                   (account_id)
#  index_crm_commission_sheets_on_account_id_and_period_month  (account_id,period_month)
#  index_crm_commission_sheets_on_owner_id                     (owner_id)
#  uniq_commission_sheet_owner_month                           (account_id,owner_id,period_month) UNIQUE
#
class Crm::CommissionSheet < ApplicationRecord
  STATUSES = %w[DRAFT SUBMITTED APPROVED RETURNED].freeze
  EDITABLE_STATUSES = %w[DRAFT RETURNED].freeze

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :manager, class_name: 'User', optional: true
  belongs_to :returned_by, class_name: 'User', optional: true

  has_many :items, -> { order(:position, :id) },
           class_name: 'Crm::CommissionItem', foreign_key: :crm_commission_sheet_id,
           dependent: :destroy, inverse_of: :sheet
  accepts_nested_attributes_for :items, allow_destroy: true

  validates :period_month, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :owner_id, uniqueness: { scope: [:account_id, :period_month],
                                      message: '该业务员本月已有提成表' }

  scope :for_month, ->(date) { where(period_month: date.beginning_of_month..date.end_of_month) }
  scope :owned_by, ->(user_id) { where(owner_id: user_id) }
  scope :submitted_or_after, -> { where(status: %w[SUBMITTED APPROVED]) }

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  # 提交审批：仅草稿/退回态可提交。
  def submit!
    update!(status: 'SUBMITTED', submitted_at: Time.current,
            return_reason: nil, returned_at: nil, returned_by_id: nil)
  end

  # 主管通过。
  def approve!(by:)
    update!(status: 'APPROVED', manager_id: by.id, approved_at: Time.current)
  end

  # 主管退回：回到草稿态，记录原因/人/时间，业务员改后重走审批。
  def return!(reason:, by:)
    update!(status: 'RETURNED', return_reason: reason,
            returned_at: Time.current, returned_by_id: by.id,
            manager_id: nil, approved_at: nil)
  end

  # 汇总：全表总计。销售额分两口径——RMB 单看 sales_rmb；美金单(USD/EUR 等非 CNY)看订单金额净值
  # （收款=订单+运费，故订单金额即净销售），供列表 RMB/USD 两列并列展示。
  def totals
    rows = items.to_a
    {
      shipping_micros: rows.sum { |i| i.shipping_micros.to_i },
      received_rmb_micros: rows.sum { |i| i.received_rmb_micros.to_i },
      sales_rmb_micros: rows.sum { |i| i.sales_rmb_micros.to_i },
      sales_usd_micros: rows.reject { |i| i.currency == 'CNY' }.sum { |i| i.order_amount_micros.to_i },
      count: rows.size
    }
  end
end
