class AddPiFieldsToCrmSalesOrders < ActiveRecord::Migration[7.1]
  def change
    # pi_no：形式发票号（PI No.），来自读取的 PI；order_no 是系统自动生成的内部单号，二者不同。
    add_column :crm_sales_orders, :pi_no, :string
    # line_items：订单明细（品名/规格/数量/单价/金额），从 PI 识别得来，内联存订单上（不进关系表）。
    add_column :crm_sales_orders, :line_items, :jsonb, null: false, default: []
  end
end
