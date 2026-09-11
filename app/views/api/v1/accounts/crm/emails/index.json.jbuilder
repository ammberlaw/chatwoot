json.meta do
  json.count @emails_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @emails do |email|
    json.partial! 'api/v1/models/crm_email', formats: [:json], resource: email,
                                             counterparty_type: @counterparty_types[email.id],
                                             counterparty_name: @counterparty_names[email.id],
                                             last_open: @last_opens[email.id],
                                             distributions: @distributions[email.id] || []
  end
end
