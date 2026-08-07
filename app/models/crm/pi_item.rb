# PI 明细行：一行一个产品（MODEL / DESCRIPTION / 数量 / 单价 / 金额 + 产品图片）。
# 金额 = 数量 × 单价，保存前自动算。
# == Schema Information
#
# Table name: crm_pi_items
#
#  id                :bigint           not null, primary key
#  amount_micros     :bigint
#  description       :text
#  model             :string
#  position          :integer          default(0), not null
#  quantity          :decimal(12, 2)
#  unit_price_micros :bigint
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_pi_id         :bigint           not null
#
# Indexes
#
#  index_crm_pi_items_on_account_id  (account_id)
#  index_crm_pi_items_on_crm_pi_id   (crm_pi_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (crm_pi_id => crm_pis.id)
#
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
