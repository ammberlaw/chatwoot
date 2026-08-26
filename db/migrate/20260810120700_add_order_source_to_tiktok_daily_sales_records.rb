class AddOrderSourceToTiktokDailySalesRecords < ActiveRecord::Migration[7.1]
  # 订单来源四拆分（用于看板饼图）：联盟直播/联盟/商品卡/商家。四项之和=总订单。
  # 存量记录默认 0（无拆分），仅对以后录入生效。
  def change
    add_column :tiktok_daily_sales_records, :alliance_live_orders, :integer, default: 0, null: false
    add_column :tiktok_daily_sales_records, :alliance_orders, :integer, default: 0, null: false
    add_column :tiktok_daily_sales_records, :product_card_orders, :integer, default: 0, null: false
    add_column :tiktok_daily_sales_records, :merchant_orders, :integer, default: 0, null: false
  end
end
