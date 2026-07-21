# == Schema Information
#
# Table name: mes_shipment_items
#
#  id             :bigint           not null, primary key
#  qty            :decimal(16, 3)   not null
#  remark         :text
#  unit           :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  crm_product_id :bigint
#  shipment_id    :bigint           not null
#
# Indexes
#
#  index_mes_shipment_items_on_account_id      (account_id)
#  index_mes_shipment_items_on_crm_product_id  (crm_product_id)
#  index_mes_shipment_items_on_shipment_id     (shipment_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (shipment_id => mes_shipments.id) ON DELETE => cascade
#
class Mes::ShipmentItem < ApplicationRecord
  belongs_to :account
  belongs_to :shipment, class_name: 'Mes::Shipment', inverse_of: :shipment_items
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true

  before_validation :inherit_account

  validates :qty, presence: true, numericality: { greater_than: 0 }

  private

  def inherit_account
    self.account_id ||= shipment&.account_id
  end
end
