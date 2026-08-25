# 付款单：实际付给供应商的钱。核销到应付台账后台账余额才动。
class Erp::PaymentRecord < ApplicationRecord
  NORMAL = 'NORMAL'.freeze
  VOID = 'VOID'.freeze
  METHODS = Erp::ReceiptRecord::METHODS
  METHOD_LABELS = Erp::ReceiptRecord::METHOD_LABELS

  belongs_to :account
  belongs_to :mes_supplier, class_name: 'Mes::Supplier'
  belongs_to :cash_account, class_name: 'Erp::CashAccount', optional: true
  belongs_to :recorded_by, class_name: 'User', optional: true
  has_many :allocations, class_name: 'Erp::PaymentAllocation',
                         dependent: :destroy, inverse_of: :payment_record

  validates :payment_no, presence: true, uniqueness: { scope: :account_id }
  validates :amount_micros, numericality: { greater_than: 0 }
  validates :method, inclusion: { in: METHODS }
  validates :paid_at, presence: true

  before_validation :assign_payment_no, on: :create

  scope :normal, -> { where(status: NORMAL) }

  def allocated_micros
    allocations.sum(:amount_micros)
  end

  def unallocated_micros
    amount_micros - allocated_micros
  end

  def voidable?
    status == NORMAL
  end

  private

  def assign_payment_no
    return if payment_no.present?

    self.payment_no = Erp::DocumentNumber.next(account, 'PV', :erp_payment_records, :payment_no)
  end
end
