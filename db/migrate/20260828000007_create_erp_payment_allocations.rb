class CreateErpPaymentAllocations < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_payment_allocations do |t|
      t.references :account, null: false, index: true
      t.bigint :payment_record_id, null: false, index: true
      t.bigint :payable_id, null: false, index: true
      t.bigint :amount_micros, null: false
      t.timestamps
    end
    add_foreign_key :erp_payment_allocations, :erp_payment_records, column: :payment_record_id, on_delete: :cascade
    add_foreign_key :erp_payment_allocations, :erp_payables, column: :payable_id, on_delete: :restrict
  end
end
