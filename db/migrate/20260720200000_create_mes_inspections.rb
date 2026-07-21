class CreateMesInspections < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_inspections do |t|
      t.references :account, null: false, index: true
      t.string :kind, null: false # IQC / IPQC / FQC / AGING
      t.string :item_type # MATERIAL / PRODUCT
      t.bigint :mes_material_id, index: true
      t.bigint :crm_product_id, index: true
      t.bigint :production_order_id, index: true
      t.bigint :purchase_order_id, index: true
      t.decimal :inspected_qty, precision: 14, scale: 3, default: 0, null: false
      t.decimal :passed_qty, precision: 14, scale: 3, default: 0, null: false
      t.decimal :failed_qty, precision: 14, scale: 3, default: 0, null: false
      t.string :result # PASS / FAIL / CONDITIONAL
      t.text :defect_reason
      t.boolean :need_rework, default: false, null: false
      t.bigint :inspector_id
      t.datetime :inspected_at
      t.text :remark
      t.timestamps
    end

    add_index :mes_inspections, [:account_id, :kind]
    add_foreign_key :mes_inspections, :mes_materials, column: :mes_material_id, on_delete: :nullify
    add_foreign_key :mes_inspections, :crm_products, column: :crm_product_id, on_delete: :nullify
    add_foreign_key :mes_inspections, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_inspections, :mes_purchase_orders, column: :purchase_order_id, on_delete: :nullify
    add_foreign_key :mes_inspections, :users, column: :inspector_id, on_delete: :nullify
  end
end
