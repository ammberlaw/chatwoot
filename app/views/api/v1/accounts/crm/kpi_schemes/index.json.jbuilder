json.payload do
  json.array! @schemes do |scheme|
    json.partial! 'api/v1/models/crm_kpi_scheme', formats: [:json], resource: scheme
  end
end
