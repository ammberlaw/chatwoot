class Mes::PurchaseItem < ApplicationRecord
  belongs_to :account
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', inverse_of: :purchase_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true

  before_validation :inherit_account, :compute_amount
  after_save :sync_total
  after_destroy :sync_total

  validates :qty, presence: true, numericality: { greater_than: 0 }

  private

  def inherit_account
    self.account_id ||= purchase_order&.account_id
  end

  def compute_amount
    self.amount_micros = ((qty || 0).to_d * (rate_micros || 0)).round
  end

  def sync_total
    purchase_order.recompute_total!
  end
end
