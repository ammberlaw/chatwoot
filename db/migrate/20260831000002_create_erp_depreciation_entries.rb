class CreateErpDepreciationEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_depreciation_entries do |t|
      t.references :account, null: false, index: true
      t.bigint :fixed_asset_id, null: false, index: true
      t.string :period, null: false          # YYYY-MM
      t.bigint :amount_micros, null: false
      t.bigint :voucher_id                   # 当月汇总折旧凭证
      t.timestamps

      t.index %i[account_id period]
      t.index %i[fixed_asset_id period], unique: true
    end
    add_foreign_key :erp_depreciation_entries, :erp_fixed_assets, column: :fixed_asset_id, on_delete: :cascade
  end
end
