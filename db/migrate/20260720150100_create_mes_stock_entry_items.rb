class CreateMesStockEntryItems < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_stock_entry_items do |t|
      t.references :account, null: false, index: true
      t.bigint :stock_entry_id, null: false, index: true
      t.string :item_type, null: false
      t.bigint :mes_material_id, index: true
      t.bigint :crm_product_id, index: true
      t.decimal :qty, precision: 16, scale: 3, null: false
      t.decimal :received_qty, precision: 16, scale: 3
      t.string :unit
      t.bigint :warehouse_id
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_stock_entry_items, :mes_stock_entries, column: :stock_entry_id, on_delete: :cascade
    add_foreign_key :mes_stock_entry_items, :mes_materials, column: :mes_material_id, on_delete: :nullify
    add_foreign_key :mes_stock_entry_items, :crm_products, column: :crm_product_id, on_delete: :nullify
  end
end
