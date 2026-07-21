class CreateMesSerialNumbers < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_serial_numbers do |t|
      t.references :account, null: false, index: true
      t.string :sn, null: false
      t.bigint :production_order_id, index: true
      t.bigint :crm_product_id, index: true
      t.bigint :shipment_id, index: true
      t.string :status, default: 'IN_STOCK', null: false # IN_STOCK / SHIPPED / RMA
      t.text :remark
      t.timestamps
    end

    add_index :mes_serial_numbers, [:account_id, :sn], unique: true
    add_foreign_key :mes_serial_numbers, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_serial_numbers, :crm_products, column: :crm_product_id, on_delete: :nullify
    add_foreign_key :mes_serial_numbers, :mes_shipments, column: :shipment_id, on_delete: :nullify
  end
end
