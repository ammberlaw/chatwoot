# 应收台账：一张销售订单一条账（也可脱离订单手工建）。
# received_amount_micros **只经核销代码路径维护**（Erp::AllocationService），页面与接口都不许直接改。
# == Schema Information
#
# Table name: erp_receivables
#
#  id                     :bigint           not null, primary key
#  currency               :string           default("CNY"), not null
#  exchange_rate          :decimal(12, 6)   default(1.0), not null
#  receivable_no          :string           not null
#  received_amount_micros :bigint           default(0), not null
#  remark                 :text
#  status                 :string           default("UNPAID"), not null
#  total_amount_micros    :bigint           default(0), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  crm_customer_id        :bigint           not null
#  crm_sales_order_id     :bigint
#  owner_id               :bigint
#
# Indexes
#
#  index_erp_receivables_on_account_and_order             (account_id,crm_sales_order_id) UNIQUE WHERE (crm_sales_order_id IS NOT NULL)
#  index_erp_receivables_on_account_id                    (account_id)
#  index_erp_receivables_on_account_id_and_receivable_no  (account_id,receivable_no) UNIQUE
#  index_erp_receivables_on_account_id_and_status         (account_id,status)
#  index_erp_receivables_on_crm_customer_id               (crm_customer_id)
#  index_erp_receivables_on_crm_sales_order_id            (crm_sales_order_id)
#
class Erp::Receivable < ApplicationRecord
  UNPAID = 'UNPAID'.freeze
  PARTIAL = 'PARTIAL'.freeze
  PAID = 'PAID'.freeze
  STATUSES = [UNPAID, PARTIAL, PAID].freeze
  STATUS_LABELS = { UNPAID => '未收款', PARTIAL => '部分收款', PAID => '已收清' }.freeze

  # 折本位币的规范口径（与 Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL 同约定）。
  # 本表金额存的是**原币**，跨币种求和必须过这个 SQL；直接 sum 原币列＝把美元当人民币 1:1 加。
  BASE_TOTAL_MICROS_SQL = 'ROUND(erp_receivables.total_amount_micros * COALESCE(erp_receivables.exchange_rate, 1))'.freeze
  BASE_RECEIVED_MICROS_SQL = 'ROUND(erp_receivables.received_amount_micros * COALESCE(erp_receivables.exchange_rate, 1))'.freeze

  belongs_to :account
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :crm_customer, class_name: 'Crm::Customer'
  belongs_to :owner, class_name: 'User', optional: true
  has_many :installments, -> { order(:seq, :id) }, class_name: 'Erp::ReceivableInstallment',
                                                   foreign_key: :receivable_id, dependent: :destroy, inverse_of: :receivable
  has_many :allocations, class_name: 'Erp::ReceiptAllocation',
                         dependent: :restrict_with_error, inverse_of: :receivable

  accepts_nested_attributes_for :installments, allow_destroy: true

  validates :receivable_no, presence: true, uniqueness: { scope: :account_id }
  validates :total_amount_micros, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_validation :assign_receivable_no, on: :create

  scope :open, -> { where(status: [UNPAID, PARTIAL]) }

  def outstanding_micros
    total_amount_micros - received_amount_micros
  end

  def derived_status
    return PAID if outstanding_micros <= 0
    return PARTIAL if received_amount_micros.positive?

    UNPAID
  end

  private

  def assign_receivable_no
    return if receivable_no.present?

    self.receivable_no = Erp::DocumentNumber.next(account, 'AR', :erp_receivables, :receivable_no)
  end
end
