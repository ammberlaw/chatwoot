class CreateTiktokProfitRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_profit_records do |t|
      t.bigint :account_id, null: false
      t.bigint :shop_id, null: false                        # 归属店铺（→ 部门收口）
      t.string :product_model, null: false                  # 产品型号（如 K717）
      t.string :stat_month, null: false                     # 统计月份 YYYY-MM
      t.string :period_note                                 # 统计时间备注（如 2月1日-7月20日）
      t.integer :recorded_quantity, null: false, default: 0 # 已入账数量（台）
      t.integer :platform_negative, null: false, default: 0 # 平台统计负数（已扣数量）
      t.decimal :recorded_amount, precision: 14, scale: 2, default: 0    # 已入账金额（原币）
      t.string :currency, null: false, default: 'PHP'
      t.decimal :recorded_amount_cny, precision: 14, scale: 2, default: 0 # 已入账金额换算 RMB 快照
      t.decimal :fx_rate, precision: 14, scale: 6, default: 0
      t.decimal :cost_unit_price, precision: 14, scale: 2, default: 0     # 出厂成本单价（CNY）
      t.decimal :influencer_commission, precision: 14, scale: 2, default: 0 # 达人佣金（CNY）
      t.decimal :platform_commission, precision: 14, scale: 2, default: 0   # 平台佣金（CNY）
      t.decimal :tax, precision: 14, scale: 2, default: 0                   # 税费（CNY）
      t.decimal :other_cost, precision: 14, scale: 2, default: 0            # 其它成本支出（CNY）
      t.text :other_cost_note                               # 其它成本备注
      t.bigint :creator_id                                  # 录入人
      t.timestamps
    end

    add_index :tiktok_profit_records, %i[account_id shop_id stat_month product_model], unique: true, name: 'idx_tiktok_profit_uniq'
    add_index :tiktok_profit_records, %i[account_id stat_month]
    add_foreign_key :tiktok_profit_records, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :tiktok_profit_records, :tiktok_shops, column: :shop_id, on_delete: :cascade
    add_foreign_key :tiktok_profit_records, :users, column: :creator_id, on_delete: :nullify
  end
end
