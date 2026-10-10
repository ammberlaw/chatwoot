json.payload do
  json.array! @bom_costs do |row|
    json.partial! 'api/v1/models/erp_bom_cost', formats: [:json], resource: row
  end
end
json.meta do
  json.count @bom_costs_count
end
