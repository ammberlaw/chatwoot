json.meta do
  json.pending_count @pending_count
end

json.payload do
  json.array! @orders do |order|
    json.id order.id
    json.order_no order.order_no
    json.name order.name
    json.status order.status
    json.order_date order.order_date
    json.delivery_date order.delivery_date
    json.currency order.order_currency
    json.exchange_rate order.exchange_rate
    json.amount_micros order.order_amount_micros
    json.crm_customer_id order.crm_customer_id
    json.customer_name order.crm_customer&.name
    json.owner_id order.owner_id
    json.owner_name order.owner&.crm_name.presence || order.owner&.name
  end
end
