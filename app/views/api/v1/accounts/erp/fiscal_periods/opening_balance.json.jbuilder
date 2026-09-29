if @voucher
  json.voucher_no @voucher.voucher_no
  # 凭证落在启用日前一天，回显时还原成启用日——否则页面每存一次就把启用日往前挪一天。
  json.as_of @voucher.voucher_date + 1
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
      # 往来单位要回显：不带出来的话重进页面这两栏是空的，再存一次就把往来挂失了。
      json.crm_customer_id line.crm_customer_id
      json.crm_customer_name line.crm_customer&.name
      json.mes_supplier_id line.mes_supplier_id
      json.mes_supplier_name line.mes_supplier&.name
    end
  end
else
  json.voucher_no nil
  json.rows []
end
