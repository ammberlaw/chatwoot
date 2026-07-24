json.payload do
  json.array! @signatures do |signature|
    json.partial! 'api/v1/models/crm_email_signature', formats: [:json], resource: signature
  end
end
