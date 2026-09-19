# 费用报销打款：员工在 OA 提「费用报销」审批 → 审批通过 → 财务在 ERP 点打款，
# 这张单承接财务侧的三件事：付钱（出纳日记账）、入账（自动凭证）、归集（挂订单的进成本）。
#
# 为什么不是独立报销单：员工已经在 OA 报销了（生产在用），再造一套单据＝两个入口。
# 所以 ERP 只补审批之后断掉的那一截。
# == Schema Information
#
# Table name: erp_expense_payouts
#
#  id                        :bigint           not null, primary key
#  amount_micros             :bigint           not null
#  cost_type                 :string
#  paid_at                   :date             not null
#  payout_no                 :string           not null
#  remark                    :text
#  status                    :string           default("NORMAL"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  cash_account_id           :bigint           not null
#  crm_sales_order_id        :bigint
#  expense_ledger_account_id :bigint           not null
#  oa_approval_request_id    :bigint           not null
#  recorded_by_id            :bigint
#
# Indexes
#
#  index_erp_expense_payouts_on_account_id                (account_id)
#  index_erp_expense_payouts_on_account_id_and_paid_at    (account_id,paid_at)
#  index_erp_expense_payouts_on_account_id_and_payout_no  (account_id,payout_no) UNIQUE
#  index_erp_expense_payouts_on_crm_sales_order_id        (crm_sales_order_id)
#  index_erp_expense_payouts_on_oa_approval_request_id    (oa_approval_request_id)
#  uniq_erp_expense_payout_live_request                   (account_id,oa_approval_request_id) UNIQUE WHERE ((status)::text <> 'VOID'::text)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => erp_cash_accounts.id)
#  fk_rails_...  (crm_sales_order_id => crm_sales_orders.id) ON DELETE => nullify
#  fk_rails_...  (expense_ledger_account_id => erp_ledger_accounts.id)
#  fk_rails_...  (oa_approval_request_id => oa_approval_requests.id) ON DELETE => cascade
#
class Erp::ExpensePayout < ApplicationRecord
  NORMAL = 'NORMAL'.freeze
  VOID = 'VOID'.freeze

  # 报销一律本位币：外币报销公司没有这个场景，硬编成 CNY 省掉一整套折算。
  # （CashLedgerService / AutoVoucherService 要读这两个字段，以方法形式满足其接口。）
  CURRENCY = 'CNY'.freeze

  belongs_to :account
  belongs_to :approval_request, class_name: 'Oa::ApprovalRequest', foreign_key: :oa_approval_request_id,
                                inverse_of: false
  belongs_to :expense_ledger_account, class_name: 'Erp::LedgerAccount'
  belongs_to :cash_account, class_name: 'Erp::CashAccount'
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :recorded_by, class_name: 'User', optional: true

  validates :payout_no, presence: true, uniqueness: { scope: :account_id }
  validates :amount_micros, numericality: { greater_than: 0 }
  validates :paid_at, presence: true
  validates :status, inclusion: { in: [NORMAL, VOID] }
  validates :cost_type, inclusion: { in: Erp::OrderCost::COST_TYPES }, allow_blank: true

  before_validation :assign_payout_no, on: :create

  scope :normal, -> { where(status: NORMAL) }

  def currency = CURRENCY
  def exchange_rate = 1.to_d

  # CashLedgerService 拿它拼流水摘要。
  def method_label = '报销打款'

  def voidable? = status == NORMAL

  # 报销人（出纳日记账的对方单位一栏显示人名）。
  def applicant = approval_request&.applicant

  private

  def assign_payout_no
    return if payout_no.present?

    self.payout_no = Erp::DocumentNumber.next(account, 'EX', :erp_expense_payouts, :payout_no)
  end
end
