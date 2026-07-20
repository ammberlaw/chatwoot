class CreateMesBomItems < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_bom_items do |t|
      t.references :account, null: false, index: true
      t.bigint :bom_id, null: false, index: true
      t.bigint :mes_material_id, index: true
      t.decimal :qty, precision: 14, scale: 3, null: false
      t.string :unit
      t.bigint :rate_micros
      t.bigint :amount_micros
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_bom_items, :mes_boms, column: :bom_id, on_delete: :cascade
    add_foreign_key :mes_bom_items, :mes_materials, column: :mes_material_id, on_delete: :nullify
  end
end
