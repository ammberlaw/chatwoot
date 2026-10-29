json.id resource.id
json.receipt_no resource.receipt_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.cash_account_id resource.cash_account_id
json.amount_micros resource.amount_micros
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.bank_charge_micros resource.bank_charge_micros
json.method resource[:method]
json.method_label resource.method_label
json.received_at resource.received_at
json.reference_no resource.reference_no
json.status resource.status
json.status_label resource.status == Erp::ReceiptRecord::VOID ? '已作废' : '正常'
json.recorded_by_name resource.recorded_by&.finance_display_name
json.allocated_micros resource.allocated_micros
json.unallocated_micros resource.unallocated_micros
json.remark resource.remark
json.allocations do
  json.array! resource.allocations do |allocation|
    json.id allocation.id
    json.receivable_id allocation.receivable_id
    json.receivable_no allocation.receivable&.receivable_no
    json.amount_micros allocation.amount_micros
  end
end
