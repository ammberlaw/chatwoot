class CreateMesStockBalances < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_stock_balances do |t|
      t.references :account, null: false, index: true
      t.string :item_type, null: false
      t.bigint :mes_material_id, index: true
      t.bigint :crm_product_id, index: true
      t.bigint :warehouse_id, null: false
      t.decimal :qty, precision: 16, scale: 3, default: 0, null: false
      t.timestamps
    end

    add_index :mes_stock_balances,
              [:account_id, :item_type, :mes_material_id, :crm_product_id, :warehouse_id],
              unique: true, nulls_not_distinct: true, name: 'index_mes_stock_balances_unique'
  end
end
