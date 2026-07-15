json.payload do
  json.array! @employees do |employee|
    json.partial! 'api/v1/models/crm_employee', formats: [:json], resource: employee
  end
end
