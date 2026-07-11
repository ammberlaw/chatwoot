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

  before_validation :snapshot_product, on: :create

  validates :name, presence: true

  private

  def snapshot_product
    return if product.blank?

    self.product_name_snapshot ||= product.name
    self.spec_snapshot ||= product.specification
    self.name = product.name if name.blank?
  end
end
