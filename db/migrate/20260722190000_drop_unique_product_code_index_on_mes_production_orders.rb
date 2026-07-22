class DropUniqueProductCodeIndexOnMesProductionOrders < ActiveRecord::Migration[7.1]
  def up
    # 允许同款产品多单共用一个产品编码（贴近 ERP 产品主数据）：去唯一，保留普通索引供查询/ERP 对接。
    remove_index :mes_production_orders, name: 'index_mes_production_orders_on_account_and_product_code'
    add_index :mes_production_orders, [:account_id, :product_code],
              name: 'index_mes_production_orders_on_account_and_product_code'
  end

  def down
    remove_index :mes_production_orders, name: 'index_mes_production_orders_on_account_and_product_code'
    add_index :mes_production_orders, [:account_id, :product_code],
              unique: true, where: 'product_code IS NOT NULL',
              name: 'index_mes_production_orders_on_account_and_product_code'
  end
end
