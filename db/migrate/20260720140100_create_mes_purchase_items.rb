class CreateMesPurchaseItems < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_purchase_items do |t|
      t.references :account, null: false, index: true
      t.bigint :purchase_order_id, null: false, index: true
      t.bigint :mes_material_id, index: true
      t.decimal :qty, precision: 14, scale: 3, null: false
      t.string :unit
      t.bigint :rate_micros
      t.bigint :amount_micros
      t.decimal :received_qty, precision: 14, scale: 3, default: 0, null: false
      t.text :remark
      t.timestamps
    end

    add_foreign_key :mes_purchase_items, :mes_purchase_orders, column: :purchase_order_id, on_delete: :cascade
    add_foreign_key :mes_purchase_items, :mes_materials, column: :mes_material_id, on_delete: :nullify
  end
end
