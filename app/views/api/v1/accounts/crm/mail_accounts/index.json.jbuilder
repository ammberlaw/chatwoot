json.payload do
  json.array! @mail_accounts do |mail_account|
    json.partial! 'api/v1/models/crm_mail_account', formats: [:json], resource: mail_account
  end
end
