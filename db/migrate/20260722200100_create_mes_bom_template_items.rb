class CreateMesBomTemplateItems < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_bom_template_items do |t|
      t.references :account, null: false, index: true
      t.bigint :bom_template_id, null: false, index: true
      t.string :material_no
      t.string :material_name
      t.string :specification
      t.string :unit
      t.decimal :qty, precision: 14, scale: 3, null: false
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_bom_template_items, :mes_bom_templates, column: :bom_template_id, on_delete: :cascade
  end
end
