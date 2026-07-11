json.payload do
  json.array! @targets do |target|
    json.partial! 'api/v1/models/crm_sales_target', formats: [:json], resource: target
  end
end
