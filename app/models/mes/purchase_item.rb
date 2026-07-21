# == Schema Information
#
# Table name: mes_purchase_items
#
#  id                :bigint           not null, primary key
#  amount_micros     :bigint
#  qty               :decimal(14, 3)   not null
#  rate_micros       :bigint
#  received_qty      :decimal(14, 3)   default(0.0), not null
#  remark            :text
#  unit              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  mes_material_id   :bigint
#  purchase_order_id :bigint           not null
#
# Indexes
#
#  index_mes_purchase_items_on_account_id         (account_id)
#  index_mes_purchase_items_on_mes_material_id    (mes_material_id)
#  index_mes_purchase_items_on_purchase_order_id  (purchase_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => cascade
#
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
