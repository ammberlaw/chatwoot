class CreateMesPurchaseOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :mes_purchase_orders do |t|
      t.references :account, null: false, index: true
      t.string :po_no, null: false
      t.bigint :mes_supplier_id, index: true
      t.bigint :production_order_id, index: true
      t.string :status, default: 'DRAFT', null: false
      t.datetime :expected_date
      t.datetime :follow_up_date
      t.boolean :has_exception, default: false, null: false
      t.text :exception_note
      t.bigint :total_amount_micros
      t.bigint :owner_id, index: true
      t.text :remark
      t.timestamps
    end

    add_index :mes_purchase_orders, [:account_id, :po_no], unique: true
    add_index :mes_purchase_orders, [:account_id, :status]
    add_foreign_key :mes_purchase_orders, :mes_suppliers, column: :mes_supplier_id, on_delete: :nullify
    add_foreign_key :mes_purchase_orders, :mes_production_orders, column: :production_order_id, on_delete: :nullify
    add_foreign_key :mes_purchase_orders, :users, column: :owner_id, on_delete: :nullify
  end
end
