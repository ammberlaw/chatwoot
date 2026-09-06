class CreateErpPayables < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_payables do |t|
      t.references :account, null: false, index: true
      t.string :payable_no, null: false              # AP-YYYYMMDD-NN
      t.bigint :mes_purchase_order_id, index: true   # 来源采购单（可空：运费/外协等对公应付）
      t.bigint :mes_supplier_id, null: false, index: true
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.bigint :total_amount_micros, null: false, default: 0
      t.bigint :paid_amount_micros, null: false, default: 0
      t.string :status, null: false, default: 'UNPAID' # UNPAID/PARTIAL/PAID
      t.date :due_date
      t.text :remark
      t.timestamps

      t.index %i[account_id payable_no], unique: true
      t.index %i[account_id status]
    end
  end
end
