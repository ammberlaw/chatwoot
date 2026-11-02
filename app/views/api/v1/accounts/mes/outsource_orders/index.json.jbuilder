json.payload do
  json.array! @outsource_orders do |order|
    json.partial! 'api/v1/models/mes_outsource_order', resource: order
  end
end
json.meta do
  json.count @outsource_orders_count
end
