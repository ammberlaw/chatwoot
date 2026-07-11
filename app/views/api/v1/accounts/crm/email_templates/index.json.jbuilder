json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/models/crm_email_template', formats: [:json], resource: template
  end
end
