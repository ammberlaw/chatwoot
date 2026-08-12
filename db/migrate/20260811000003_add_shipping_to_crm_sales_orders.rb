class AddShippingToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    # 运费（订单币种，微分）。订单金额为净销售额（不含运费）；收款额 = 订单金额 + 运费。
    # 带单进提成表时自动带出运费/收款额，提成基数只看净销售额、不含运费。
    add_column :crm_sales_orders, :shipping_micros, :bigint
  end
end
