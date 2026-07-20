class CreateMesBoms < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_boms do |t|
      t.references :account, null: false, index: true
      t.string :bom_no, null: false
      t.bigint :crm_product_id, index: true
      t.decimal :base_qty, precision: 14, scale: 3, default: 1, null: false
      t.string :unit
      t.integer :estimated_lead_days
      t.bigint :total_material_cost_micros
      t.boolean :is_active, default: true, null: false
      t.boolean :is_default, default: false, null: false
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_index :mes_boms, [:account_id, :bom_no], unique: true
    add_foreign_key :mes_boms, :crm_products, column: :crm_product_id, on_delete: :nullify
    add_foreign_key :mes_boms, :users, column: :owner_id, on_delete: :nullify
  end
end
