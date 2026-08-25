# 付款单：实际付给供应商的钱。核销到应付台账后台账余额才动。
# == Schema Information
#
# Table name: erp_payment_records
#
#  id                 :bigint           not null, primary key
#  amount_micros      :bigint           not null
#  bank_charge_micros :bigint           default(0), not null
#  currency           :string           default("CNY"), not null
#  exchange_rate      :decimal(12, 6)   default(1.0), not null
#  method             :string           default("TT"), not null
#  paid_at            :date             not null
#  payment_no         :string           not null
#  reference_no       :string
#  remark             :text
#  status             :string           default("NORMAL"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  cash_account_id    :bigint
#  mes_supplier_id    :bigint           not null
#  recorded_by_id     :bigint
#
# Indexes
#
#  index_erp_payment_records_on_account_id                 (account_id)
#  index_erp_payment_records_on_account_id_and_paid_at     (account_id,paid_at)
#  index_erp_payment_records_on_account_id_and_payment_no  (account_id,payment_no) UNIQUE
#  index_erp_payment_records_on_cash_account_id            (cash_account_id)
#  index_erp_payment_records_on_mes_supplier_id            (mes_supplier_id)
#
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

  # 收付方式中文名。⚠️ 用 self[:method] 取值：method 与 Object#method 同名，直接写 method 会拿到方法对象。
  def method_label
    METHOD_LABELS[self[:method]]
  end

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
