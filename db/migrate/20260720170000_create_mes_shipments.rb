class CreateMesShipments < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_shipments do |t|
      t.references :account, null: false, index: true
      t.string :shipment_no, null: false
      t.bigint :crm_sales_order_id, index: true
      t.bigint :crm_customer_id, index: true
      t.bigint :production_order_id, index: true
      t.bigint :warehouse_id
      t.string :status, default: 'DRAFT', null: false
      t.datetime :notified_at
      t.datetime :shipped_at
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_index :mes_shipments, [:account_id, :shipment_no], unique: true
    add_foreign_key :mes_shipments, :crm_sales_orders, column: :crm_sales_order_id, on_delete: :nullify
    add_foreign_key :mes_shipments, :crm_customers, column: :crm_customer_id, on_delete: :nullify
    add_foreign_key :mes_shipments, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_shipments, :users, column: :owner_id, on_delete: :nullify
  end
end
