json.id resource.id
json.receivable_no resource.receivable_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.crm_sales_order_id resource.crm_sales_order_id
json.order_no resource.crm_sales_order&.order_no
# 台账要能独立对账：PI 号是财务认的号，型号/日期/订单状态决定这笔钱该不该催、催谁。
# 没有这几列就只能逐条点进订单详情看，一张张对。
json.pi_no resource.crm_sales_order&.pi_no
json.order_status resource.crm_sales_order&.status
json.order_date resource.crm_sales_order&.order_date
json.delivery_date resource.crm_sales_order&.delivery_date
# 型号：列表只摆第一项 + 共几项，全部明细放 product_names 给悬浮用。
json.product_summary resource.crm_sales_order&.product_summary
json.product_names resource.crm_sales_order&.product_names
# 这笔应收在总账里有没有对应的收入凭证：建账时出的（Erp::Receivable）或出库时出的（Mes::Shipment）。
# 台账上看不出有没有入账，就只能去凭证列表逐条翻。
json.revenue_voucher_no resource.revenue_voucher&.voucher_no
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
