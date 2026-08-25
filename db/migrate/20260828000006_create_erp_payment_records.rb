class CreateErpPaymentRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_payment_records do |t|
      t.references :account, null: false, index: true
      t.string :payment_no, null: false              # PV-YYYYMMDD-NN
      t.bigint :mes_supplier_id, null: false, index: true
      t.bigint :cash_account_id, index: true
      t.bigint :amount_micros, null: false
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.bigint :bank_charge_micros, null: false, default: 0
      t.string :method, null: false, default: 'TT'
      t.date :paid_at, null: false
      t.string :reference_no
      t.string :status, null: false, default: 'NORMAL'
      t.bigint :recorded_by_id
      t.text :remark
      t.timestamps

      t.index %i[account_id payment_no], unique: true
      t.index %i[account_id paid_at]
    end
  end
end
