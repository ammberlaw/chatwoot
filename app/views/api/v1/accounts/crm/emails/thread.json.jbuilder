json.payload do
  json.array! @thread_emails do |email|
    json.partial! 'api/v1/models/crm_email', formats: [:json], resource: email
  end
end
