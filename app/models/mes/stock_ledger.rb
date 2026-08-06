# 库存流水台账：每次过账一条不可变记录。
# == Schema Information
#
# Table name: mes_stock_ledgers
#
#  id              :bigint           not null, primary key
#  balance_after   :decimal(16, 3)   not null
#  item_type       :string           not null
#  posted_at       :datetime         not null
#  qty_change      :decimal(16, 3)   not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  crm_product_id  :bigint
#  mes_material_id :bigint
#  stock_entry_id  :bigint
#  warehouse_id    :bigint           not null
#
# Indexes
#
#  idx_on_account_id_warehouse_id_item_type_8c18176a8b  (account_id,warehouse_id,item_type)
#  index_mes_stock_ledgers_on_account_id                (account_id)
#  index_mes_stock_ledgers_on_crm_product_id            (crm_product_id)
#  index_mes_stock_ledgers_on_mes_material_id           (mes_material_id)
#  index_mes_stock_ledgers_on_stock_entry_id            (stock_entry_id)
#
class Mes::StockLedger < ApplicationRecord
  belongs_to :account
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :stock_entry, class_name: 'Mes::StockEntry', optional: true
end
