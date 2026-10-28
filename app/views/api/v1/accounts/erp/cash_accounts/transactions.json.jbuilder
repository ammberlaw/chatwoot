json.meta do
  json.count @transactions_count
  json.truncated @truncated
end
json.payload do
  json.array! @transactions do |transaction|
    json.id transaction.id
    json.cash_account_id transaction.cash_account_id
    json.cash_account_name transaction.cash_account&.name
    json.direction transaction.direction
    json.amount_micros transaction.amount_micros
    json.currency transaction.currency
    json.exchange_rate transaction.exchange_rate
    json.happened_at transaction.happened_at
    json.summary transaction.summary
    json.counterparty transaction.counterparty
    json.source_type transaction.source_type
    json.source_id transaction.source_id
    json.created_by_name transaction.created_by&.name.presence || transaction.created_by&.crm_name
  end
end
