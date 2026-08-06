# PI 明细行：一行一个产品（MODEL / DESCRIPTION / 数量 / 单价 / 金额 + 产品图片）。
# 金额 = 数量 × 单价，保存前自动算。
class Crm::PiItem < ApplicationRecord
  belongs_to :account
  belongs_to :pi, class_name: 'Crm::Pi', foreign_key: :crm_pi_id, inverse_of: :pi_items

  has_one_attached :picture

  before_validation :inherit_account, on: :create
  before_validation :compute_amount

  private

  def inherit_account
    self.account_id ||= pi&.account_id
  end

  def compute_amount
    self.amount_micros =
      quantity && unit_price_micros ? (quantity * unit_price_micros).round : nil
  end
end
