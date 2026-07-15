json.payload do
  json.array! @sheets do |sheet|
    json.partial! 'api/v1/models/crm_kpi_sheet', formats: [:json], resource: sheet
  end
end
