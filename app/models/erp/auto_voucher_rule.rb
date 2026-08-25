# 自动凭证规则：业务单据落库 → 按规则生成**待过账凭证**进队列 → 财务审一眼过账。
# 财务从「录凭证」变成「审凭证」，这是对金蝶的降维打击点（ERP_SPEC §8.3）。
#
# config 里可覆盖科目映射（如手续费想进「财务费用-手续费」以外的明细科目）；
# 不填就按科目的 account_type 找默认科目。
class Erp::AutoVoucherRule < ApplicationRecord
  RECEIPT = 'RECEIPT'.freeze
  PAYMENT = 'PAYMENT'.freeze
  CASH_TRANSFER = 'CASH_TRANSFER'.freeze
  EVENT_KEYS = [RECEIPT, PAYMENT, CASH_TRANSFER].freeze

  DEFAULTS = {
    RECEIPT => { name: '收款单 → 借 货币资金 / 贷 应收账款', keys: %w[fee_account_id receivable_account_id] },
    PAYMENT => { name: '付款单 → 借 应付账款 / 贷 货币资金', keys: %w[fee_account_id payable_account_id] },
    CASH_TRANSFER => { name: '内部划转 → 借 转入账户 / 贷 转出账户', keys: [] }
  }.freeze

  belongs_to :account

  validates :event_key, inclusion: { in: EVENT_KEYS }, uniqueness: { scope: :account_id }
  validates :name, presence: true

  # 首访自动建三条预置规则（默认全部启用）。
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
