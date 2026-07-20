json.meta do
  json.count @production_orders_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @production_orders do |production_order|
    json.partial! 'api/v1/models/mes_production_order', formats: [:json], resource: production_order
  end
end
