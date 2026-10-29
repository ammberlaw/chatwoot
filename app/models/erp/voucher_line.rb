# 分录行：凭证的借贷明细。原币金额 × 汇率 = 本位币金额（base_amount_micros），
# 借贷平衡以本位币为准（外币单据按录入时汇率快照折算，事后改汇率不重算历史，见 §13-8）。
# == Schema Information
#
# Table name: erp_voucher_lines
#
#  id                 :bigint           not null, primary key
#  amount_micros      :bigint           not null
#  base_amount_micros :bigint           not null
#  cash_flow_item     :string
#  currency           :string           default("CNY"), not null
#  direction          :string           not null
#  exchange_rate      :decimal(12, 6)   default(1.0), not null
#  position           :integer          default(0), not null
#  summary            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  crm_customer_id    :bigint
#  crm_sales_order_id :bigint
#  department_id      :bigint
#  ledger_account_id  :bigint           not null
#  member_id          :bigint
#  mes_supplier_id    :bigint
#  voucher_id         :bigint           not null
#
# Indexes
#
#  index_erp_voucher_lines_on_account_id                        (account_id)
#  index_erp_voucher_lines_on_account_id_and_cash_flow_item     (account_id,cash_flow_item)
#  index_erp_voucher_lines_on_account_id_and_ledger_account_id  (account_id,ledger_account_id)
#  index_erp_voucher_lines_on_crm_customer_id                   (crm_customer_id)
#  index_erp_voucher_lines_on_crm_sales_order_id                (crm_sales_order_id)
#  index_erp_voucher_lines_on_department_id                     (department_id)
#  index_erp_voucher_lines_on_ledger_account_id                 (ledger_account_id)
#  index_erp_voucher_lines_on_member_id                         (member_id)
#  index_erp_voucher_lines_on_mes_supplier_id                   (mes_supplier_id)
#  index_erp_voucher_lines_on_voucher_id                        (voucher_id)
#
# Foreign Keys
#
#  fk_rails_...  (ledger_account_id => erp_ledger_accounts.id) ON DELETE => restrict
#  fk_rails_...  (voucher_id => erp_vouchers.id) ON DELETE => cascade
#
class Erp::VoucherLine < ApplicationRecord
  DEBIT = 'DEBIT'.freeze
  CREDIT = 'CREDIT'.freeze
  DIRECTIONS = [DEBIT, CREDIT].freeze

  # 1 分 = 10,000 micros。**本位币金额一律取整到分**（金蝶同口径）：
  # 汇率是 6 位小数，1000 USD × 7.123456 = 7123.456 元，带厘。
  # 对方按 7123.46 录，两边差 0.004 元过不了账，而报错里两个数都显示成 7123.46——
  # 财务看到「借方 7123.46 / 贷方 7123.46，借贷不平」根本没法排查。
  CENT = 10_000

  belongs_to :account
  belongs_to :voucher, class_name: 'Erp::Voucher', inverse_of: :lines
  belongs_to :ledger_account, class_name: 'Erp::LedgerAccount'
  # 管理维度（都可空）：维度明细账与往来对账靠它们切片。
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true
  belongs_to :crm_sales_order, class_name: 'Crm::SalesOrder', optional: true
  belongs_to :department, class_name: 'Org::Department', optional: true
  belongs_to :member, class_name: 'User', optional: true

  # 平衡行倒挤标记（非持久化）：置真时用调用方给的 base_amount_micros，不按 原币×汇率 重算。
  attr_accessor :explicit_base

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :cash_flow_item, inclusion: { in: Erp::CashFlowItem::CODES }, allow_blank: true
  # 期末调汇分录是原币 0、只动本位币的（见 Erp::RevaluationService），所以原币放行 0；
  # 本位币仍然必须为正，空行照样进不来。
  validates :amount_micros, numericality: { greater_than_or_equal_to: 0 }
  validates :base_amount_micros, numericality: { greater_than: 0 }
  validate :validate_postable_account

  before_validation :assign_account_and_base_amount

  # 折本位币一律到分：调汇等直接给 base 的地方也走这里，口径统一。
  def self.round_to_cent(value)
    (value.to_d / CENT).round * CENT
  end

  def dimension_value(dimension)
    case dimension
    when 'customer' then crm_customer_id
    when 'supplier' then mes_supplier_id
    when 'order' then crm_sales_order_id
    when 'department' then department_id
    when 'member' then member_id
    end
  end

  private

  def assign_account_and_base_amount
    self.account_id ||= voucher&.account_id
    self.currency = 'CNY' if currency.blank?
    self.exchange_rate = 1 if exchange_rate.blank? || exchange_rate.to_d.zero?
    self.base_amount_micros = self.class.round_to_cent(amount_micros * exchange_rate.to_d) unless base_given_directly?
  end

  # 调汇分录原币是 0、本位币由调用方直接给，乘出来只会是 0，不能覆盖。
  # explicit_base：外币多行凭证里「平衡行」由调用方按各行 base 之和倒挤本位币，保证借贷严格相等
  #   （否则各行分别 round(原币×汇率) 相加≠合并 round，差 1 分致凭证不平过不了账）。
  def base_given_directly?
    explicit_base || amount_micros.blank? || (amount_micros.zero? && base_amount_micros.to_i.positive?)
  end

  def validate_postable_account
    return if ledger_account.blank?

    errors.add(:ledger_account_id, '分类科目不能直接记账，请选到末级明细科目') if ledger_account.is_group?
    errors.add(:ledger_account_id, "科目「#{ledger_account.label}」已停用") unless ledger_account.is_active?
    return if ledger_account.currency.blank? || ledger_account.currency == currency

    errors.add(:currency, "科目「#{ledger_account.label}」是 #{ledger_account.currency} 外币科目，币种须一致")
  end

  # 往来科目的客户/供应商**不再强制必填**（2026-10-29 财务两次要求，原话「这里不要搞成必填项」）。
  #
  # 代价说在前面：不挂单位的那几行，应收台账按客户查欠款、应付按供应商对账都统计不到，
  # 账簿总数仍然对得上（账簿只认科目），但「这个客户还欠多少」会漏掉它们。
  # 财务知道这个代价、仍然要求去掉——实际录凭证时很多行就是挂不上具体往来单位，
  # 卡在这儿连存都存不了，比统计漏几行更难受。
  #
  # 校验撤了但维度字段都还在，想挂照样挂；要找哪些行没挂，用应收/应付台账对一遍。
  # 真要收回去，把 `validate :validate_required_dimensions` 加回来即可。
  def required_dimension_missing?
    dimension = ledger_account&.required_dimension
    dimension.present? && dimension_value(dimension).blank?
  end
end
