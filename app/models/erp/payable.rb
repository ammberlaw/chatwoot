# 应付台账：按采购单 × 供应商建账（一张采购单多个供应商就拆多条），也可脱离采购单手工建。
# paid_amount_micros 只经核销代码路径维护（Erp::AllocationService）。
class Erp::Payable < ApplicationRecord
  UNPAID = 'UNPAID'.freeze
  PARTIAL = 'PARTIAL'.freeze
  PAID = 'PAID'.freeze
  STATUSES = [UNPAID, PARTIAL, PAID].freeze
  STATUS_LABELS = { UNPAID => '未付款', PARTIAL => '部分付款', PAID => '已付清' }.freeze

  belongs_to :account
  belongs_to :mes_purchase_order, class_name: 'Mes::PurchaseOrder', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier'
  has_many :allocations, class_name: 'Erp::PaymentAllocation',
                         dependent: :restrict_with_error, inverse_of: :payable

  validates :payable_no, presence: true, uniqueness: { scope: :account_id }
  validates :total_amount_micros, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_payable_no, on: :create

  scope :open, -> { where(status: [UNPAID, PARTIAL]) }

  def outstanding_micros
    total_amount_micros - paid_amount_micros
  end

  def derived_status
    return PAID if outstanding_micros <= 0
    return PARTIAL if paid_amount_micros.positive?

    UNPAID
  end

  private

  def assign_payable_no
    return if payable_no.present?

    self.payable_no = Erp::DocumentNumber.next(account, 'AP', :erp_payables, :payable_no)
  end
end
