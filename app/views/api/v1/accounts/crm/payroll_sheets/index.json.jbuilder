json.payload do
  json.array! @sheets do |row|
    json.partial! 'api/v1/models/crm_payroll_sheet', formats: [:json], resource: row
  end
end
json.meta { json.count @sheets_count }
