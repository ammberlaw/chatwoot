json.payload do
  json.array! @contacts do |contact|
    json.partial! 'api/v1/models/crm_contact', formats: [:json], resource: contact
  end
end
