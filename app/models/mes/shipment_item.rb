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
