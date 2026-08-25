# 资金账户：银行户/现金/PayPal/西联。每个账户映射一个会计科目，自动凭证按它记账。
# 余额 = 期初 + Σ流入 - Σ流出（日记账只增不改，见 ERP_SPEC §13-7）。
class Erp::CashAccount < ApplicationRecord
  KINDS = %w[BANK CASH PAYPAL WESTERN_UNION OTHER].freeze
  KIND_LABELS = {
    'BANK' => '银行账户', 'CASH' => '现金', 'PAYPAL' => 'PayPal',
    'WESTERN_UNION' => '西联', 'OTHER' => '其他'
  }.freeze

  belongs_to :account
  belongs_to :ledger_account, class_name: 'Erp::LedgerAccount', optional: true
  has_many :transactions, -> { order(happened_at: :desc, id: :desc) }, class_name: 'Erp::CashTransaction',
                                                                       foreign_key: :cash_account_id,
                                                                       dependent: :restrict_with_error,
                                                                       inverse_of: :cash_account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :kind, inclusion: { in: KINDS }

  scope :active, -> { where(is_active: true) }

  def balance_micros
    opening_balance_micros + transactions.where(direction: 'IN').sum(:amount_micros) -
      transactions.where(direction: 'OUT').sum(:amount_micros)
  end
end
