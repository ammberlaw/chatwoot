json.id resource.id
json.payment_no resource.payment_no
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.cash_account_id resource.cash_account_id
json.amount_micros resource.amount_micros
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.bank_charge_micros resource.bank_charge_micros
json.method resource.method
json.method_label Erp::PaymentRecord::METHOD_LABELS[resource.method]
json.paid_at resource.paid_at
json.reference_no resource.reference_no
json.status resource.status
json.status_label resource.status == Erp::PaymentRecord::VOID ? '已作废' : '正常'
json.recorded_by_name resource.recorded_by&.crm_name.presence || resource.recorded_by&.name
json.allocated_micros resource.allocated_micros
json.unallocated_micros resource.unallocated_micros
json.remark resource.remark
json.allocations do
  json.array! resource.allocations do |allocation|
    json.id allocation.id
    json.payable_id allocation.payable_id
    json.payable_no allocation.payable&.payable_no
    json.amount_micros allocation.amount_micros
  end
end
