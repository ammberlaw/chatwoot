# 收款单（水单）：客户实际到账记录。核销到应收台账后台账余额才动。
# 已核销的收款单不可改删，只能作废（VOID）——作废时自动回滚核销与台账余额。
# == Schema Information
#
# Table name: erp_receipt_records
#
#  id                 :bigint           not null, primary key
#  amount_micros      :bigint           not null
#  bank_charge_micros :bigint           default(0), not null
#  currency           :string           default("CNY"), not null
#  exchange_rate      :decimal(12, 6)   default(1.0), not null
#  method             :string           default("TT"), not null
#  receipt_no         :string           not null
#  received_at        :date             not null
#  reference_no       :string
#  remark             :text
#  status             :string           default("NORMAL"), not null
#  trade_assurance_no :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  cash_account_id    :bigint
#  crm_customer_id    :bigint           not null
#  recorded_by_id     :bigint
#
# Indexes
#
#  index_erp_receipt_records_on_account_and_trade_assurance  (account_id,trade_assurance_no)
#  index_erp_receipt_records_on_account_id                   (account_id)
#  index_erp_receipt_records_on_account_id_and_receipt_no    (account_id,receipt_no) UNIQUE
#  index_erp_receipt_records_on_account_id_and_received_at   (account_id,received_at)
#  index_erp_receipt_records_on_cash_account_id              (cash_account_id)
#  index_erp_receipt_records_on_crm_customer_id              (crm_customer_id)
#
class Erp::ReceiptRecord < ApplicationRecord
  include Erp::SettlementRecord
  NORMAL = 'NORMAL'.freeze
  VOID = 'VOID'.freeze
  METHODS = %w[TT LC WESTERN_UNION PAYPAL RMB OTHER].freeze
  METHOD_LABELS = {
    'TT' => '电汇 TT', 'LC' => '信用证 LC', 'WESTERN_UNION' => '西联', 'PAYPAL' => 'PayPal',
    'RMB' => '人民币转账', 'OTHER' => '其他'
  }.freeze

  # 折本位币的规范口径（与 Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL 同约定）。
  # 本表金额存的是**原币**，跨币种求和必须过这个 SQL；直接 sum 原币列＝把美元当人民币 1:1 加。
  BASE_AMOUNT_MICROS_SQL = 'ROUND(erp_receipt_records.amount_micros * COALESCE(erp_receipt_records.exchange_rate, 1))'.freeze

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

  # 收付方式中文名。⚠️ 用 self[:method] 取值：method 与 Object#method 同名，直接写 method 会拿到方法对象。
  def method_label
    METHOD_LABELS[self[:method]]
  end

  def allocated_micros
    allocations.sum(:amount_micros)
  end

  # 尚未核销到台账的金额（预收/待认领）。
  def unallocated_micros
    allocatable_micros - allocated_micros
  end

  # 到账金额不含手续费；可核销按客户实际偿付的毛额。
  def allocatable_micros = amount_micros + bank_charge_micros.to_i
  def cash_amount_micros = amount_micros

  def voidable?
    status == NORMAL
  end

  private

  def assign_receipt_no
    return if receipt_no.present?

    self.receipt_no = Erp::DocumentNumber.next(account, 'RV', :erp_receipt_records, :receipt_no)
  end
end
