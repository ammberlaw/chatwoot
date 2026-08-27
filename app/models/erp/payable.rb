# 应付台账：按采购单 × 供应商建账（一张采购单多个供应商就拆多条），也可脱离采购单手工建。
# paid_amount_micros 只经核销代码路径维护（Erp::AllocationService）。
# == Schema Information
#
# Table name: erp_payables
#
#  id                    :bigint           not null, primary key
#  currency              :string           default("CNY"), not null
#  due_date              :date
#  exchange_rate         :decimal(12, 6)   default(1.0), not null
#  paid_amount_micros    :bigint           default(0), not null
#  payable_no            :string           not null
#  remark                :text
#  status                :string           default("UNPAID"), not null
#  total_amount_micros   :bigint           default(0), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  mes_purchase_order_id :bigint
#  mes_supplier_id       :bigint           not null
#
# Indexes
#
#  index_erp_payables_on_account_id                 (account_id)
#  index_erp_payables_on_account_id_and_payable_no  (account_id,payable_no) UNIQUE
#  index_erp_payables_on_account_id_and_status      (account_id,status)
#  index_erp_payables_on_mes_purchase_order_id      (mes_purchase_order_id)
#  index_erp_payables_on_mes_supplier_id            (mes_supplier_id)
#
class Erp::Payable < ApplicationRecord
  UNPAID = 'UNPAID'.freeze
  PARTIAL = 'PARTIAL'.freeze
  PAID = 'PAID'.freeze
  STATUSES = [UNPAID, PARTIAL, PAID].freeze
  STATUS_LABELS = { UNPAID => '未付款', PARTIAL => '部分付款', PAID => '已付清' }.freeze

  # 折本位币的规范口径（与 Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL 同约定）。
  # 本表金额存的是**原币**，跨币种求和必须过这个 SQL；直接 sum 原币列＝把美元当人民币 1:1 加。
  BASE_TOTAL_MICROS_SQL = 'ROUND(erp_payables.total_amount_micros * COALESCE(erp_payables.exchange_rate, 1))'.freeze
  BASE_PAID_MICROS_SQL = 'ROUND(erp_payables.paid_amount_micros * COALESCE(erp_payables.exchange_rate, 1))'.freeze

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
