class CreateErpReceivableInstallments < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_receivable_installments do |t|
      t.references :account, null: false, index: true
      t.bigint :receivable_id, null: false, index: true
      t.integer :seq, null: false, default: 1
      t.string :kind, null: false, default: 'BALANCE'  # DEPOSIT 订金 / BALANCE 尾款 / OTHER
      t.bigint :amount_micros, null: false, default: 0
      t.string :due_basis, null: false, default: 'FIXED' # ORDER_DATE/BEFORE_SHIPMENT/AFTER_SHIPMENT/BL_COPY/FIXED
      t.integer :due_days
      t.date :due_date
      t.string :status, null: false, default: 'PENDING'  # PENDING/DUE_SOON/OVERDUE/SETTLED
      t.text :remark
      t.timestamps

      t.index %i[account_id due_date]
    end
    add_foreign_key :erp_receivable_installments, :erp_receivables, column: :receivable_id, on_delete: :cascade
  end
end
