class CreateErpReceiptAllocations < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_receipt_allocations do |t|
      t.references :account, null: false, index: true
      t.bigint :receipt_record_id, null: false, index: true
      t.bigint :receivable_id, null: false, index: true
      t.bigint :amount_micros, null: false
      t.timestamps
    end
    add_foreign_key :erp_receipt_allocations, :erp_receipt_records, column: :receipt_record_id, on_delete: :cascade
    add_foreign_key :erp_receipt_allocations, :erp_receivables, column: :receivable_id, on_delete: :restrict
  end
end
