json.payload do
  json.order do
    json.id @order.id
    json.order_no @order.order_no
    json.name @order.name
    json.status @order.status
    json.order_kind @order.order_kind
    json.order_date @order.order_date
    json.delivery_date @order.delivery_date
    json.currency @order.order_currency
    json.exchange_rate @order.exchange_rate
    json.amount_micros @order.order_amount_micros
    json.shipping_micros @order.shipping_micros
    json.pi_no @order.pi_no
    json.payment_term @order.payment_term
    json.remark @order.remark
    json.customer_id @order.crm_customer_id
    json.customer_name @order.crm_customer&.name
    json.owner_name @order.owner&.crm_name.presence || @order.owner&.name
    json.opportunity_name @order.crm_opportunity&.name
  end

  # 订单明细存在 crm_sales_orders.line_items（jsonb）：品名/规格/数量/单价/金额。
  # 编码(sku)由控制器解析后挂在 @line_items_with_sku——明细只存 crm_product_id，
  # 财务看不出是哪个料号。
  json.line_items @line_items_with_sku

  # 挂在这张销售订单上的 MES 单据（生产订单含阶段与出入库、出货单含出了什么货）。
  json.production_orders @trace[:production_orders]
  json.shipments @trace[:shipments]

  if @order_receivable
    json.receivable do
      json.id @order_receivable.id
      json.receivable_no @order_receivable.receivable_no
      json.total_amount_micros @order_receivable.total_amount_micros
      json.received_amount_micros @order_receivable.received_amount_micros
    end
  else
    json.receivable nil
  end
end
