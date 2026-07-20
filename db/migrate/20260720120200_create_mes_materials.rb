class CreateMesMaterials < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_materials do |t|
      t.references :account, null: false, index: true
      t.string :material_no, null: false
      t.string :name, null: false
      t.string :category
      t.string :specification
      t.string :unit, null: false
      t.bigint :cost_price_micros
      t.string :currency, default: 'CNY'
      t.decimal :safety_stock, precision: 14, scale: 3
      t.bigint :default_supplier_id, index: true
      t.boolean :is_active, default: true, null: false
      t.text :remark
      t.timestamps
    end

    add_index :mes_materials, [:account_id, :material_no], unique: true
    add_foreign_key :mes_materials, :mes_suppliers, column: :default_supplier_id, on_delete: :nullify
  end
end
