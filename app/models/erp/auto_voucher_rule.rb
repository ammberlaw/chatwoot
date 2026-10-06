# 自动凭证规则：业务单据落库 → 按规则生成**待过账凭证**进队列 → 财务审一眼过账。
# 财务从「录凭证」变成「审凭证」，这是对金蝶的降维打击点（ERP_SPEC §8.3）。
#
# config 里可覆盖科目映射（如手续费想进「财务费用-手续费」以外的明细科目）；
# 不填就按科目的 account_type 找默认科目。
# == Schema Information
#
# Table name: erp_auto_voucher_rules
#
#  id         :bigint           not null, primary key
#  config     :jsonb            not null
#  event_key  :string           not null
#  is_active  :boolean          default(TRUE), not null
#  name       :string           not null
#  remark     :text
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_erp_auto_voucher_rules_on_account_id                (account_id)
#  index_erp_auto_voucher_rules_on_account_id_and_event_key  (account_id,event_key) UNIQUE
#
class Erp::AutoVoucherRule < ApplicationRecord
  RECEIPT = 'RECEIPT'.freeze
  PAYMENT = 'PAYMENT'.freeze
  CASH_TRANSFER = 'CASH_TRANSFER'.freeze
  EXPENSE_PAYOUT = 'EXPENSE_PAYOUT'.freeze
  # 业务单据驱动的三个事件（财务 2026-10-06 拍板：收入在销售出库时点确认）。
  SHIPMENT_REVENUE = 'SHIPMENT_REVENUE'.freeze
  SHIPMENT_COST = 'SHIPMENT_COST'.freeze
  STOCK_RECEIPT = 'STOCK_RECEIPT'.freeze
  EVENT_KEYS = [RECEIPT, PAYMENT, CASH_TRANSFER, EXPENSE_PAYOUT,
                SHIPMENT_REVENUE, SHIPMENT_COST, STOCK_RECEIPT].freeze

  DEFAULTS = {
    RECEIPT => { name: '收款单 → 借 货币资金 / 贷 应收账款', keys: %w[fee_account_id receivable_account_id] },
    PAYMENT => { name: '付款单 → 借 应付账款 / 贷 货币资金', keys: %w[fee_account_id payable_account_id] },
    CASH_TRANSFER => { name: '内部划转 → 借 转入账户 / 贷 转出账户', keys: [] },
    EXPENSE_PAYOUT => { name: '报销打款 → 借 费用科目 / 贷 货币资金', keys: [] },
    SHIPMENT_REVENUE => { name: '销售出库 → 借 应收账款 / 贷 主营业务收入 + 销项税',
                          keys: %w[revenue_account_id tax_account_id receivable_account_id] },
    SHIPMENT_COST => { name: '销售出库 → 借 主营业务成本 / 贷 库存商品',
                       keys: %w[cogs_account_id inventory_account_id] },
    STOCK_RECEIPT => { name: '采购入库/退货 → 借 存货科目 / 贷 应付账款（退货红字）',
                       keys: %w[payable_account_id] }
  }.freeze

  belongs_to :account

  validates :event_key, inclusion: { in: EVENT_KEYS }, uniqueness: { scope: :account_id }
  validates :name, presence: true

  # 首访自动建预置规则（默认全部启用）；新增规则的账号下次访问时自动补建。
  def self.ensure_defaults!(account)
    DEFAULTS.each do |event_key, spec|
      account.erp_auto_voucher_rules.find_or_create_by!(event_key: event_key) do |rule|
        rule.name = spec[:name]
        rule.is_active = true
      end
    end
    account.erp_auto_voucher_rules.order(:event_key)
  end
end
