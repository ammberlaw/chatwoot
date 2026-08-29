class CreateMesPurchaseRequisitions < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_purchase_requisitions do |t|
      t.references :account, null: false, index: true
      t.string :req_no, null: false
      t.bigint :production_order_id
      t.string :purpose, null: false, default: 'ORDER' # ORDER 按单 / STOCK 备库存 / ADHOC 临时
      t.string :product_line
      t.string :status, null: false, default: 'DRAFT'
      t.bigint :owner_id
      t.date :expected_date
      t.text :remark
      t.timestamps
    end
    add_index :mes_purchase_requisitions, [:account_id, :req_no], unique: true
    add_index :mes_purchase_requisitions, :production_order_id
    add_foreign_key :mes_purchase_requisitions, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_purchase_requisitions, :users, column: :owner_id, on_delete: :nullify

    create_table :mes_purchase_requisition_items do |t|
      t.references :account, null: false, index: true
      t.bigint :purchase_requisition_id, null: false
      t.string :item_type, null: false, default: 'MATERIAL' # MATERIAL 物料 / PRODUCT 外购成品
      t.bigint :mes_material_id
      t.bigint :crm_product_id
      t.bigint :mes_supplier_id
      t.string :material_no
      t.string :material_name
      t.string :specification
      t.string :unit
      t.decimal :required_qty, precision: 14, scale: 3, null: false, default: 0
      t.decimal :suggested_qty, precision: 14, scale: 3, null: false, default: 0
      t.decimal :ordered_qty, precision: 14, scale: 3, null: false, default: 0
      t.text :remark
      t.timestamps
    end
    add_index :mes_purchase_requisition_items, :purchase_requisition_id, name: 'idx_mes_pr_items_on_pr_id'
    add_foreign_key :mes_purchase_requisition_items, :mes_purchase_requisitions, column: :purchase_requisition_id, on_delete: :cascade
    add_foreign_key :mes_purchase_requisition_items, :mes_materials, column: :mes_material_id, on_delete: :nullify
    add_foreign_key :mes_purchase_requisition_items, :crm_products, column: :crm_product_id, on_delete: :nullify
    add_foreign_key :mes_purchase_requisition_items, :mes_suppliers, column: :mes_supplier_id, on_delete: :nullify

    add_column :mes_purchase_orders, :purchase_requisition_id, :bigint
    add_index :mes_purchase_orders, :purchase_requisition_id
    add_foreign_key :mes_purchase_orders, :mes_purchase_requisitions, column: :purchase_requisition_id, on_delete: :nullify
  end
end
