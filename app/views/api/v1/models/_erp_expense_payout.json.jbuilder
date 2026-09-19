json.id resource.id
json.payout_no resource.payout_no
json.oa_approval_request_id resource.oa_approval_request_id
json.request_title resource.approval_request&.title
json.applicant_name resource.applicant&.crm_name.presence || resource.applicant&.name
json.amount_micros resource.amount_micros
json.currency resource.currency
json.expense_ledger_account_id resource.expense_ledger_account_id
json.expense_account_name resource.expense_ledger_account&.name
json.expense_account_code resource.expense_ledger_account&.code
json.cash_account_id resource.cash_account_id
json.cash_account_name resource.cash_account&.name
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.cost_type resource.cost_type
json.cost_type_label Erp::OrderCost::COST_TYPE_LABELS[resource.cost_type]
json.paid_at resource.paid_at
json.status resource.status
json.status_label resource.status == Erp::ExpensePayout::VOID ? '已作废' : '正常'
json.remark resource.remark
json.recorded_by_name resource.recorded_by&.crm_name.presence || resource.recorded_by&.name
