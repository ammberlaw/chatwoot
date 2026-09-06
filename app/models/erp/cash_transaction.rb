# 出纳日记账：与库存流水同哲学——**只增不改**，余额永远等于流水累计（§13-7）。
# 收付款单作废时不删流水，而是补一条方向相反的冲销流水，留痕可追。
# == Schema Information
#
# Table name: erp_cash_transactions
#
#  id              :bigint           not null, primary key
#  amount_micros   :bigint           not null
#  counterparty    :string
#  currency        :string           default("CNY"), not null
#  direction       :string           not null
#  exchange_rate   :decimal(12, 6)   default(1.0), not null
#  happened_at     :date             not null
#  source_type     :string
#  summary         :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  cash_account_id :bigint           not null
#  created_by_id   :bigint
#  source_id       :bigint
#
# Indexes
#
#  index_erp_cash_transactions_on_account_id                  (account_id)
#  index_erp_cash_transactions_on_account_id_and_happened_at  (account_id,happened_at)
#  index_erp_cash_transactions_on_cash_account_id             (cash_account_id)
#  index_erp_cash_transactions_on_source_type_and_source_id   (source_type,source_id)
#
# Foreign Keys
#
#  fk_rails_...  (cash_account_id => erp_cash_accounts.id) ON DELETE => restrict
#
class Erp::CashTransaction < ApplicationRecord
  IN = 'IN'.freeze
  OUT = 'OUT'.freeze
  DIRECTIONS = [IN, OUT].freeze

  belongs_to :account
  belongs_to :cash_account, class_name: 'Erp::CashAccount', inverse_of: :transactions
  belongs_to :created_by, class_name: 'User', optional: true

  validates :direction, inclusion: { in: DIRECTIONS }
  validates :amount_micros, numericality: { greater_than: 0 }
  validates :happened_at, presence: true

  def base_amount_micros
    (amount_micros * exchange_rate).round
  end
end
