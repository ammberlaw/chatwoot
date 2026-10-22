# 交货方式：这单货怎么送到客户手上（物流发货 / 车辆配送 / 客户自提）。
# 仓管备货、安排车辆、通知客户来提都要看它，以前只能写在备注里，出库的人还得翻。
class AddDeliveryMethodToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    add_column :crm_sales_orders, :delivery_method, :string
  end
end
