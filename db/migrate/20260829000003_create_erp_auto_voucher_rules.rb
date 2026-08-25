class CreateErpAutoVoucherRules < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_auto_voucher_rules do |t|
      t.references :account, null: false, index: true
      t.string :event_key, null: false          # RECEIPT / PAYMENT / CASH_TRANSFER
      t.string :name, null: false
      t.boolean :is_active, null: false, default: true
      t.jsonb :config, null: false, default: {} # 科目映射覆盖（不填走 account_type 默认）
      t.text :remark
      t.timestamps

      t.index %i[account_id event_key], unique: true
    end
  end
end
