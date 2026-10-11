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
    # 运费是向客户另收的钱，订单金额里不含它（CRM 订单上单独一栏）。建账金额含运费，
    # 不摆出来财务就对不上「订单 1000、怎么建出 1080」。
    json.shipping_micros order.shipping_micros
    # 建账金额＝货款+运费+销项税，不含税单还比这个多一个税；清单上直接摆出来，
    # 免得财务看着订单金额、建出来数字不一样以为系统算错。
    json.receivable_amount_micros order.receivable_amount_micros
    json.tax_rate order.effective_tax_rate
    json.amount_includes_tax order.effective_amount_includes_tax
    json.crm_customer_id order.crm_customer_id
    json.customer_name order.crm_customer&.name
    # 与应收台账同一套列：建账前得看清「这是谁、哪国、什么货、哪张 PI」，
    # 不然只有一个订单号，财务得逐条点进订单详情才敢勾。
    json.customer_country order.crm_customer&.trade_country
    json.pi_no order.pi_no
    json.product_summary order.product_summary
    json.product_names order.product_names
    json.owner_id order.owner_id
    json.owner_name order.owner&.crm_name.presence || order.owner&.name
  end
end
