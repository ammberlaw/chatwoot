class CreateErpCashAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_cash_accounts do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false                 # 中国银行深圳分行 / 现金 / PayPal
      t.string :kind, null: false, default: 'BANK' # BANK/CASH/PAYPAL/WESTERN_UNION/OTHER
      t.string :currency, null: false, default: 'CNY'
      t.string :account_no
      t.string :bank_name
      t.bigint :ledger_account_id, index: true    # 映射的会计科目（自动凭证按它记账）
      t.bigint :opening_balance_micros, null: false, default: 0
      t.boolean :is_active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.text :remark
      t.timestamps

      t.index %i[account_id name], unique: true
    end
  end
end
