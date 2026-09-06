json.id resource.id
json.receivable_no resource.receivable_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.crm_sales_order_id resource.crm_sales_order_id
json.order_no resource.crm_sales_order&.order_no
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.total_amount_micros resource.total_amount_micros
json.received_amount_micros resource.received_amount_micros
json.outstanding_micros resource.outstanding_micros
json.status resource.status
json.status_label Erp::Receivable::STATUS_LABELS[resource.status]
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_name.presence || resource.owner&.name
json.remark resource.remark

if local_assigns[:with_installments]
  json.installments do
    json.array! resource.installments do |installment|
      json.id installment.id
      json.seq installment.seq
      json.kind installment.kind
      json.kind_label Erp::ReceivableInstallment::KIND_LABELS[installment.kind]
      json.amount_micros installment.amount_micros
      json.due_basis installment.due_basis
      json.due_basis_label Erp::ReceivableInstallment::DUE_BASIS_LABELS[installment.due_basis]
      json.due_days installment.due_days
      json.due_date installment.due_date
      json.status installment.derived_status
      json.status_label Erp::ReceivableInstallment::STATUS_LABELS[installment.derived_status]
      json.remark installment.remark
    end
  end
end
