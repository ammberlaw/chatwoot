class CreateErpVoucherLines < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_voucher_lines do |t|
      t.references :account, null: false, index: true
      t.bigint :voucher_id, null: false, index: true
      t.bigint :ledger_account_id, null: false, index: true
      t.string :direction, null: false         # DEBIT 借 / CREDIT 贷
      t.string :summary                        # 逐行摘要
      t.bigint :amount_micros, null: false     # 原币金额
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.bigint :base_amount_micros, null: false # 本位币（CNY）记账金额，借贷平衡以它为准
      t.integer :position, null: false, default: 0
      # 管理维度（按科目 dimensions 要求校验），维度明细账靠它切片
      t.bigint :crm_customer_id
      t.bigint :mes_supplier_id
      t.bigint :crm_sales_order_id
      t.bigint :department_id
      t.bigint :member_id
      t.timestamps

      t.index %i[account_id ledger_account_id]
      t.index :crm_customer_id
      t.index :mes_supplier_id
      t.index :crm_sales_order_id
    end

    add_foreign_key :erp_voucher_lines, :erp_vouchers, column: :voucher_id, on_delete: :cascade
    add_foreign_key :erp_voucher_lines, :erp_ledger_accounts, column: :ledger_account_id, on_delete: :restrict
  end
end
