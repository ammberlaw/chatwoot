class CreateMesBomTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_bom_templates do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.string :product_line, index: true
      t.decimal :base_qty, precision: 14, scale: 3, default: 1, null: false
      t.string :unit
      t.integer :purchasing_days
      t.integer :material_inbound_days
      t.integer :picking_days
      t.integer :production_days
      t.integer :fg_inbound_days
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_bom_templates, :users, column: :owner_id, on_delete: :nullify
  end
end
