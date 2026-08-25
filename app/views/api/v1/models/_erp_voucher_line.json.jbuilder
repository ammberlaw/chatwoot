json.id resource.id
json.ledger_account_id resource.ledger_account_id
json.ledger_account_code resource.ledger_account&.code
json.ledger_account_name resource.ledger_account&.name
json.direction resource.direction
json.summary resource.summary
json.amount_micros resource.amount_micros
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.base_amount_micros resource.base_amount_micros
json.position resource.position
json.dimensions resource.ledger_account&.dimensions || []
json.crm_customer_id resource.crm_customer_id
json.crm_customer_name resource.crm_customer&.name
json.mes_supplier_id resource.mes_supplier_id
json.mes_supplier_name resource.mes_supplier&.name
json.crm_sales_order_id resource.crm_sales_order_id
json.crm_sales_order_no resource.crm_sales_order&.order_no
json.department_id resource.department_id
json.department_name resource.department&.name
json.member_id resource.member_id
json.member_name resource.member&.crm_name.presence || resource.member&.name
