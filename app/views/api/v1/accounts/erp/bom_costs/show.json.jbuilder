json.payload do
  json.partial! 'api/v1/models/erp_bom_cost', formats: [:json], resource: @bom_cost
end
