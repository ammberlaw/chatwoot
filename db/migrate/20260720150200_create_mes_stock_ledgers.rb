class CreateMesStockLedgers < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_stock_ledgers do |t|
      t.references :account, null: false, index: true
      t.string :item_type, null: false
      t.bigint :mes_material_id, index: true
      t.bigint :crm_product_id, index: true
      t.bigint :warehouse_id, null: false
      t.bigint :stock_entry_id, index: true
      t.decimal :qty_change, precision: 16, scale: 3, null: false
      t.decimal :balance_after, precision: 16, scale: 3, null: false
      t.datetime :posted_at, null: false
      t.timestamps
    end

    add_index :mes_stock_ledgers, [:account_id, :warehouse_id, :item_type]
  end
end
