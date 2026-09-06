json.meta do
  json.ledger_account do
    json.partial! 'api/v1/models/erp_ledger_account', formats: [:json], resource: @ledger_account
  end
  json.opening_micros @result[:opening_micros]
  json.closing_micros @result[:closing_micros]
end

json.payload do
  json.array! @result[:rows] do |row|
    json.partial! 'api/v1/models/erp_voucher_line', formats: [:json], resource: row[:line]
    json.balance_micros row[:balance_micros]
    json.voucher_id row[:line].voucher_id
    json.voucher_no row[:line].voucher.voucher_no
    json.voucher_date row[:line].voucher.voucher_date
    json.voucher_summary row[:line].voucher.summary
  end
end
