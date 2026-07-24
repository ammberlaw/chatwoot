# == Schema Information
#
# Table name: mes_purchase_items
#
#  id                :bigint           not null, primary key
#  amount_micros     :bigint
#  arrival_date      :datetime
#  item_type         :string           default("MATERIAL"), not null
#  qty               :decimal(14, 3)   not null
#  rate_micros       :bigint
#  received_qty      :decimal(14, 3)   default(0.0), not null
#  remark            :text
#  unit              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  crm_product_id    :bigint
#  mes_material_id   :bigint
#  mes_supplier_id   :bigint
#  purchase_order_id :bigint           not null
#
# Indexes
#
#  index_mes_purchase_items_on_account_id         (account_id)
#  index_mes_purchase_items_on_crm_product_id     (crm_product_id)
#  index_mes_purchase_items_on_mes_material_id    (mes_material_id)
#  index_mes_purchase_items_on_mes_supplier_id    (mes_supplier_id)
#  index_mes_purchase_items_on_purchase_order_id  (purchase_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (mes_supplier_id => mes_suppliers.id) ON DELETE => nullify
#  fk_rails_...  (purchase_order_id => mes_purchase_orders.id) ON DELETE => cascade
#
class Mes::PurchaseItem < ApplicationRecord
  # MATERIAL=生产用料（挂 mes_material）；PRODUCT=外购成品（挂 crm_product，不经过生产部）。
  ITEM_TYPES = %w[MATERIAL PRODUCT].freeze

  belongs_to :account
  belongs_to :purchase_order, class_name: 'Mes::PurchaseOrder', inverse_of: :purchase_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :mes_supplier, class_name: 'Mes::Supplier', optional: true

  before_validation :inherit_account, :compute_amount
  after_destroy :sync_total
  after_save :sync_total

  validates :item_type, inclusion: { in: ITEM_TYPES }
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
