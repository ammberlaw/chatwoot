json.meta do
  json.dimension @dimension
  json.dimension_label Erp::LedgerAccount::DIMENSION_LABELS[@dimension]
end

json.payload do
  json.array! @rows do |row|
    json.id row[:id]
    json.name row[:name]
    json.debit_micros row[:debit_micros]
    json.credit_micros row[:credit_micros]
    json.net_micros row[:net_micros]
  end
end
