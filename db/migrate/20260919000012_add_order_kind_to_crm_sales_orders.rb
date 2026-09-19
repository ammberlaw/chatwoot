class AddOrderKindToCrmSalesOrders < ActiveRecord::Migration[7.1]
  # 订单双轨：CUSTOM 定制（转生产订单走生产脊柱）/ STOCK 库存（转现货出库单直接扣成品库存）。
  # 存量订单留空＝未分类，转单时补选；不给默认值，免得把历史库存单一股脑标成定制。
  def change
    add_column :crm_sales_orders, :order_kind, :string
    add_index :crm_sales_orders, [:account_id, :order_kind]
  end
end
