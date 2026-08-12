class CreateTiktokDailySalesRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_daily_sales_records do |t|
      t.bigint :account_id, null: false
      t.bigint :shop_id, null: false                        # 归属店铺（tiktok_shops）
      t.date :sale_date, null: false                        # 销售日期（一店一天一行）
      t.integer :total_orders, null: false, default: 0      # 总订单
      t.integer :total_units, null: false, default: 0       # 总台数
      t.decimal :sales_amount, precision: 14, scale: 2, default: 0    # 总销售额（原币种）
      t.string :currency, null: false, default: 'PHP'       # USD / EUR / PHP / CNY
      t.decimal :sales_amount_cny, precision: 14, scale: 2, default: 0 # 换算 RMB 快照（录入时定）
      t.decimal :fx_rate, precision: 14, scale: 6, default: 0          # 当时汇率快照（1 外币=? CNY）
      t.integer :cancelled_units, null: false, default: 0   # 当天取消台数
      t.integer :shipped_units, null: false, default: 0     # 实发台数
      t.integer :influencer_units, null: false, default: 0  # 达人销售台数
      t.text :remark                                         # 备注
      t.bigint :creator_id                                  # 录入人
      t.timestamps
    end

    add_index :tiktok_daily_sales_records, %i[account_id shop_id sale_date], unique: true, name: 'idx_tiktok_daily_shop_date'
    add_index :tiktok_daily_sales_records, %i[account_id sale_date]
    add_foreign_key :tiktok_daily_sales_records, :accounts, column: :account_id, on_delete: :cascade
    add_foreign_key :tiktok_daily_sales_records, :tiktok_shops, column: :shop_id, on_delete: :cascade
    add_foreign_key :tiktok_daily_sales_records, :users, column: :creator_id, on_delete: :nullify
  end
end
