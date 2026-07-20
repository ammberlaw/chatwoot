json.payload do
  json.array! @warehouses do |warehouse|
    json.partial! 'api/v1/models/mes_warehouse', formats: [:json], resource: warehouse
  end
end
