json.payload do
  json.array! @ledger_accounts do |ledger_account|
    json.partial! 'api/v1/models/erp_ledger_account', formats: [:json], resource: ledger_account
  end
end
