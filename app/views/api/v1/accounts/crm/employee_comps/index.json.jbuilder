json.payload do
  json.array! @comps do |comp|
    json.partial! 'api/v1/models/crm_employee_comp', formats: [:json], resource: comp
  end
end
