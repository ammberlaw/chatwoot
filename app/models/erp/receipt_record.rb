# 收款单（水单）：客户实际到账记录。核销到应收台账后台账余额才动。
# 已核销的收款单不可改删，只能作废（VOID）——作废时自动回滚核销与台账余额。
class Erp::ReceiptRecord < ApplicationRecord
  NORMAL = 'NORMAL'.freeze
  VOID = 'VOID'.freeze
  METHODS = %w[TT LC WESTERN_UNION PAYPAL RMB OTHER].freeze
  METHOD_LABELS = {
    'TT' => '电汇 TT', 'LC' => '信用证 LC', 'WESTERN_UNION' => '西联', 'PAYPAL' => 'PayPal',
    'RMB' => '人民币转账', 'OTHER' => '其他'
  }.freeze

  belongs_to :account
  belongs_to :crm_customer, class_name: 'Crm::Customer'
  belongs_to :cash_account, class_name: 'Erp::CashAccount', optional: true
  belongs_to :recorded_by, class_name: 'User', optional: true
  has_many :allocations, class_name: 'Erp::ReceiptAllocation',
                         dependent: :destroy, inverse_of: :receipt_record

  validates :receipt_no, presence: true, uniqueness: { scope: :account_id }
  validates :amount_micros, numericality: { greater_than: 0 }
  validates :method, inclusion: { in: METHODS }
  validates :received_at, presence: true

  before_validation :assign_receipt_no, on: :create

  scope :normal, -> { where(status: NORMAL) }

  def allocated_micros
    allocations.sum(:amount_micros)
  end

  # 尚未核销到台账的金额（预收/待认领）。
  def unallocated_micros
    amount_micros - allocated_micros
  end

  def voidable?
    status == NORMAL
  end

  private

  def assign_receipt_no
    return if receipt_no.present?

    self.receipt_no = Erp::DocumentNumber.next(account, 'RV', :erp_receipt_records, :receipt_no)
  end
end
