json.meta do
  json.count @purchase_orders_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @purchase_orders do |purchase_order|
    json.partial! 'api/v1/models/mes_purchase_order', formats: [:json], resource: purchase_order
  end
end
