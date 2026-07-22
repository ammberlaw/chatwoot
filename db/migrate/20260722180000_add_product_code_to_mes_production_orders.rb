class AddProductCodeToMesProductionOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :mes_production_orders, :product_code, :string # 产品编码（工程/PMC 编，唯一，供 ERP 共享）
    add_index :mes_production_orders, [:account_id, :product_code],
              unique: true, where: 'product_code IS NOT NULL',
              name: 'index_mes_production_orders_on_account_and_product_code'
  end
end
