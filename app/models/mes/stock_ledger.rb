# 库存流水台账：每次过账一条不可变记录。
class Mes::StockLedger < ApplicationRecord
  belongs_to :account
  belongs_to :mes_material, class_name: 'Mes::Material', optional: true
  belongs_to :crm_product, class_name: 'Crm::Product', optional: true
  belongs_to :stock_entry, class_name: 'Mes::StockEntry', optional: true
end
