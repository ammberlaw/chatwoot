json.meta do
  json.count @sales_orders_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @sales_orders do |sales_order|
    json.partial! 'api/v1/models/crm_sales_order', formats: [:json], resource: sales_order
  end
end
