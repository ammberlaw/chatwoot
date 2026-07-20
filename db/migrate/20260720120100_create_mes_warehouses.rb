class CreateMesWarehouses < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_warehouses do |t|
      t.references :account, null: false, index: true
      t.string :code, null: false
      t.string :name, null: false
      t.string :kind
      t.bigint :parent_id, index: true
      t.integer :position
      t.boolean :is_active, default: true, null: false
      t.timestamps
    end

    add_index :mes_warehouses, [:account_id, :code], unique: true
    add_foreign_key :mes_warehouses, :mes_warehouses, column: :parent_id, on_delete: :nullify
  end
end
