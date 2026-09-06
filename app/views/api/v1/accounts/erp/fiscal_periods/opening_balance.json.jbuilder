if @voucher
  json.voucher_no @voucher.voucher_no
  json.as_of @voucher.voucher_date
  json.total_debit_micros @voucher.total_debit_micros
  json.total_credit_micros @voucher.total_credit_micros
  json.rows do
    json.array! @voucher.lines do |line|
      json.ledger_account_id line.ledger_account_id
      json.code line.ledger_account&.code
      json.name line.ledger_account&.name
      json.debit_micros line.direction == Erp::VoucherLine::DEBIT ? line.amount_micros : 0
      json.credit_micros line.direction == Erp::VoucherLine::CREDIT ? line.amount_micros : 0
      json.currency line.currency
      json.exchange_rate line.exchange_rate
    end
  end
else
  json.voucher_no nil
  json.rows []
end
