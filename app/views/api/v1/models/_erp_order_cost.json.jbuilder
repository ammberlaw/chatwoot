json.id resource.id
json.crm_sales_order_id resource.crm_sales_order_id
json.order_no resource.crm_sales_order&.order_no
json.cost_type resource.cost_type
json.cost_type_label Erp::OrderCost::COST_TYPE_LABELS[resource.cost_type]
json.amount_micros resource.amount_micros
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.base_amount_micros resource.base_amount_micros
json.happened_at resource.happened_at
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.remark resource.remark
json.created_by_name resource.created_by&.crm_name.presence || resource.created_by&.name
