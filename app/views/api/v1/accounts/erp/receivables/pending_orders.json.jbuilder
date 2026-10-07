json.meta do
  json.pending_count @pending_count
  json.fiscal_start_date @fiscal_start_date
  json.before_fiscal_count @before_fiscal_count
end

json.payload do
  json.array! @orders do |order|
    json.id order.id
    json.order_no order.order_no
    json.name order.name
    json.status order.status
    json.order_date order.order_date
    json.delivery_date order.delivery_date
    json.currency order.order_currency
    json.exchange_rate order.exchange_rate
    json.amount_micros order.order_amount_micros
    # 建账金额＝收入+销项税，不含税单比订单金额多一个税；清单上直接摆出来，
    # 免得财务看着订单金额、建出来数字不一样以为系统算错。
    json.receivable_amount_micros order.receivable_amount_micros
    json.tax_rate order.effective_tax_rate
    json.amount_includes_tax order.effective_amount_includes_tax
    json.crm_customer_id order.crm_customer_id
    json.customer_name order.crm_customer&.name
    json.owner_id order.owner_id
    json.owner_name order.owner&.crm_name.presence || order.owner&.name
  end
end
