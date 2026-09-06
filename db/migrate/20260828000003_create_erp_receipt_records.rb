class CreateErpReceiptRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_receipt_records do |t|
      t.references :account, null: false, index: true
      t.string :receipt_no, null: false               # RV-YYYYMMDD-NN
      t.bigint :crm_customer_id, null: false, index: true
      t.bigint :cash_account_id, index: true          # 钱进了哪个资金账户（E4 落地后必填）
      t.bigint :amount_micros, null: false            # 到账净额（原币）
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.bigint :bank_charge_micros, null: false, default: 0 # 银行/中转手续费
      t.string :method, null: false, default: 'TT'    # TT/LC/WESTERN_UNION/PAYPAL/RMB/OTHER
      t.date :received_at, null: false
      t.string :reference_no                          # 水单号
      t.string :status, null: false, default: 'NORMAL' # NORMAL/VOID（作废留痕不删）
      t.bigint :recorded_by_id
      t.text :remark
      t.timestamps

      t.index %i[account_id receipt_no], unique: true
      t.index %i[account_id received_at]
    end
  end
end
