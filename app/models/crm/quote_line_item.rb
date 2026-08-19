# 报价明细行。对应 A-CRM(Twenty) 的 quoteLineItem（CRM_SPEC §2.3）。
# 建行时自动快照产品名称/规格，产品档案后续变更不影响已出报价。
# == Schema Information
#
# Table name: crm_quote_line_items
#
#  id                    :bigint           not null, primary key
#  amount_micros         :bigint
#  name                  :string           not null
#  product_name_snapshot :string
#  quantity              :decimal(12, 2)
#  remark                :text
#  spec_snapshot         :string
#  unit_price_micros     :bigint
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  crm_product_id        :bigint
#  crm_quote_id          :bigint           not null
#
# Indexes
#
#  index_crm_quote_line_items_on_account_id      (account_id)
#  index_crm_quote_line_items_on_crm_product_id  (crm_product_id)
#  index_crm_quote_line_items_on_crm_quote_id    (crm_quote_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (crm_quote_id => crm_quotes.id) ON DELETE => cascade
#
class Crm::QuoteLineItem < ApplicationRecord
  belongs_to :account
  belongs_to :quote, class_name: 'Crm::Quote', foreign_key: :crm_quote_id, inverse_of: :line_items
  belongs_to :product, class_name: 'Crm::Product', foreign_key: :crm_product_id, optional: true
  # 报价单明细产品图（导出 xlsx 时嵌进 PICTURE 列，同 PI）。
  has_one_attached :picture

  before_validation :inherit_account
  before_validation :snapshot_product, on: :create
  before_save :compute_amount

  validates :name, presence: true

  private

  # 嵌套创建时 account 未显式传入，从报价单继承（account_id NOT NULL）。
  def inherit_account
    self.account_id ||= quote&.account_id
  end

  # 金额 = 数量 × 单价（micros）；缺项则清空。
  def compute_amount
    self.amount_micros = quantity && unit_price_micros ? (quantity.to_d * unit_price_micros.to_i).round : nil
  end

  def snapshot_product
    return if product.blank?

    self.product_name_snapshot ||= product.name
    self.spec_snapshot ||= product.specification
    self.name = product.name if name.blank?
  end
end
