json.payload do
  json.array! @exhibitions do |exhibition|
    json.partial! 'api/v1/models/crm_exhibition', formats: [:json], resource: exhibition
  end
end
