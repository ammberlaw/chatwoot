class CreateErpCashTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_cash_transactions do |t|
      t.references :account, null: false, index: true
      t.bigint :cash_account_id, null: false, index: true
      t.string :direction, null: false             # IN 收 / OUT 付
      t.bigint :amount_micros, null: false
      t.string :currency, null: false, default: 'CNY'
      t.decimal :exchange_rate, precision: 12, scale: 6, null: false, default: 1
      t.date :happened_at, null: false
      t.string :source_type                        # 来源单据（收款单/付款单/划转）
      t.bigint :source_id
      t.string :summary
      t.string :counterparty                       # 往来单位名（快照，日记账可读）
      t.bigint :created_by_id
      t.timestamps

      t.index %i[account_id happened_at]
      t.index %i[source_type source_id]
    end
    add_foreign_key :erp_cash_transactions, :erp_cash_accounts, column: :cash_account_id, on_delete: :restrict
  end
end
