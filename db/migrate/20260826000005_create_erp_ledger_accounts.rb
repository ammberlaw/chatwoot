class CreateErpLedgerAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_ledger_accounts do |t|
      t.references :account, null: false, index: true
      t.string :code, null: false
      t.string :name, null: false
      t.string :category, null: false          # ASSET/LIABILITY/EQUITY/COST/PL（国标五大类）
      t.string :direction, null: false         # DEBIT/CREDIT 余额方向
      t.bigint :parent_id, index: true
      t.boolean :is_group, null: false, default: false
      t.string :account_type                   # CASH/BANK/RECEIVABLE/PAYABLE/... 业务钩子
      t.string :currency                       # 空=本位币 CNY；外币科目标币种，参与期末调汇
      t.string :bs_section                     # 资产负债表归属段（流动/非流动…）
      t.jsonb :dimensions, null: false, default: [] # 该科目分录行启用的管理维度
      t.boolean :is_active, null: false, default: true
      t.boolean :is_system, null: false, default: false # 预置标准科目：可停用改名，不可删
      t.integer :position, null: false, default: 0
      t.text :remark
      t.timestamps

      t.index %i[account_id code], unique: true
      t.index %i[account_id category]
    end

    add_foreign_key :erp_ledger_accounts, :erp_ledger_accounts, column: :parent_id, on_delete: :restrict
  end
end
