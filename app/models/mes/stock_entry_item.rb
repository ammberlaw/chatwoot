# == Schema Information
#
# Table name: mes_stock_entry_items
#
#  id              :bigint           not null, primary key
#  item_type       :string           not null
#  qty             :decimal(16, 3)   not null
#  received_qty    :decimal(16, 3)
#  remark          :text
#  unit            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_product_id  :bigint
#  mes_material_id :bigint
#  stock_entry_id  :bigint           not null
#  warehouse_id    :bigint
#
# Indexes
#
#  index_mes_stock_entry_items_on_account_id       (account_id)
#  index_mes_stock_entry_items_on_crm_product_id   (crm_product_id)
#  index_mes_stock_entry_items_on_mes_material_id  (mes_material_id)
#  index_mes_stock_entry_items_on_stock_entry_id   (stock_entry_id)
#
# Foreign Keys
#
#  fk_rails_...  (crm_product_id => crm_products.id) ON DELETE => nullify
#  fk_rails_...  (mes_material_id => mes_materials.id) ON DELETE => nullify
#  fk_rails_...  (stock_entry_id => mes_stock_entries.id) ON DELETE => cascade
#
class Mes::StockEntryItem < ApplicationRecord
  ITEM_TYPES = %w[MATERIAL PRODUCT].freeze

  belongs_to :account
  belongs_to :stock_entry, class_name: 'Mes::StockEntry', inverse_of: :stock_entry_items
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true

  before_validation :inherit_account

  validates :item_type, inclusion: { in: ITEM_TYPES }
  validates :qty, presence: true, numericality: { greater_than: 0 }

  # 实际过账数量：优先实收（来料核对），否则单据数量。
  def effective_qty
    (received_qty.presence || qty).to_d
  end

  private

  def inherit_account
    self.account_id ||= stock_entry&.account_id
  end
end
