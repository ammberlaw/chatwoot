# 出纳日记账：与库存流水同哲学——**只增不改**，余额永远等于流水累计（§13-7）。
# 收付款单作废时不删流水，而是补一条方向相反的冲销流水，留痕可追。
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
