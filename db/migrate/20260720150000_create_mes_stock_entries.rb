class CreateMesStockEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_stock_entries do |t|
      t.references :account, null: false, index: true
      t.string :entry_no, null: false
      t.string :purpose, null: false
      t.bigint :production_order_id, index: true
      t.bigint :purchase_order_id, index: true
      t.bigint :from_warehouse_id
      t.bigint :to_warehouse_id
      t.string :status, default: 'DRAFT', null: false
      t.datetime :posted_at
      t.boolean :is_checked, default: false, null: false
      t.bigint :checked_by_id
      t.bigint :received_by_id
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_index :mes_stock_entries, [:account_id, :entry_no], unique: true
    add_index :mes_stock_entries, [:account_id, :purpose]
    add_foreign_key :mes_stock_entries, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_stock_entries, :mes_purchase_orders, column: :purchase_order_id, on_delete: :nullify
    add_foreign_key :mes_stock_entries, :users, column: :owner_id, on_delete: :nullify
  end
end
