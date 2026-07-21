json.meta do
  json.count @shipments_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @shipments do |shipment|
    json.partial! 'api/v1/models/mes_shipment', formats: [:json], resource: shipment
  end
end
