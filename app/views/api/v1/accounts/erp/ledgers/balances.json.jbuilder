json.meta do
  json.from params[:from]
  json.to params[:to]
  json.total_debit_micros @totals[:debit_micros]
  json.total_credit_micros @totals[:credit_micros]
  json.balanced @totals[:debit_micros] == @totals[:credit_micros]
end

json.payload do
  json.array! @rows do |row|
    json.partial! 'api/v1/models/erp_ledger_account', formats: [:json], resource: row[:account]
    json.opening_micros row[:opening_micros]
    json.debit_micros row[:debit_micros]
    json.credit_micros row[:credit_micros]
    json.closing_micros row[:closing_micros]
  end
end
