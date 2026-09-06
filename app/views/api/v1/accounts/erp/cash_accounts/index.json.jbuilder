json.payload do
  json.array! @cash_accounts do |cash_account|
    json.partial! 'api/v1/models/erp_cash_account', formats: [:json], resource: cash_account
  end
end
