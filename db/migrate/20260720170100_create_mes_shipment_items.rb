class CreateMesShipmentItems < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_shipment_items do |t|
      t.references :account, null: false, index: true
      t.bigint :shipment_id, null: false, index: true
      t.bigint :crm_product_id, index: true
      t.decimal :qty, precision: 16, scale: 3, null: false
      t.string :unit
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_shipment_items, :mes_shipments, column: :shipment_id, on_delete: :cascade
    add_foreign_key :mes_shipment_items, :crm_products, column: :crm_product_id, on_delete: :nullify
  end
end
