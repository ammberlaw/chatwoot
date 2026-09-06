json.payload do
  json.array! @costs do |cost|
    json.partial! 'api/v1/models/erp_order_cost', formats: [:json], resource: cost
  end
end
