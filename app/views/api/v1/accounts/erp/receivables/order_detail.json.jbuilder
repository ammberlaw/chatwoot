json.payload do
  json.order do
    json.id @order.id
    json.order_no @order.order_no
    json.name @order.name
    json.status @order.status
    json.order_kind @order.order_kind
    json.order_date @order.order_date
    json.delivery_date @order.delivery_date
    json.currency @order.order_currency
    json.exchange_rate @order.exchange_rate
    json.amount_micros @order.order_amount_micros
    json.shipping_micros @order.shipping_micros
    json.pi_no @order.pi_no
    json.payment_term @order.payment_term
    json.remark @order.remark
    json.customer_id @order.crm_customer_id
    json.customer_name @order.crm_customer&.name
    json.owner_name @order.owner&.name.presence || @order.owner&.crm_name
    json.opportunity_name @order.crm_opportunity&.name
  end

  # 订单明细存在 crm_sales_orders.line_items（jsonb）：品名/规格/数量/单价/金额。
  # 编码(sku)由控制器解析后挂在 @line_items_with_sku——明细只存 crm_product_id，
  # 财务看不出是哪个料号。
  json.line_items @line_items_with_sku

  # 挂在这张销售订单上的 MES 单据（生产订单含阶段与出入库、出货单含出了什么货）。
  json.production_orders @trace[:production_orders]
  json.shipments @trace[:shipments]

  if @order_receivable
    json.receivable do
      json.id @order_receivable.id
      json.receivable_no @order_receivable.receivable_no
      json.total_amount_micros @order_receivable.total_amount_micros
      json.received_amount_micros @order_receivable.received_amount_micros
    end
  else
    json.receivable nil
  end

  # 采购：这单买了什么、跟谁买、花了多少 + 每颗料最近一次采购价。
  # ⚠️ 只在 ERP 的订单详情里下发（财务/管理层看）。CRM 侧的 production_trace 走另一个
  # 服务，那边一个采购字段都没有——销售端不可见成本是生态硬约束。
  json.purchase do
    json.purchase_orders(@purchase[:purchase_orders]) do |po|
      json.id po[:id]
      json.po_no po[:po_no]
      json.status po[:status]
      json.approval_status po[:approval_status]
      json.total_amount_micros po[:total_amount_micros]
      json.suppliers po[:suppliers]
      json.ordered_at po[:ordered_at]
      json.shared_with_others po[:shared_with_others]
      json.items(po[:items]) do |item|
        json.name item[:name]
        json.code item[:code]
        json.qty item[:qty]
        json.unit item[:unit]
        json.rate_micros item[:rate_micros]
        json.amount_micros item[:amount_micros]
        json.price_tax_included item[:price_tax_included]
        json.supplier_name item[:supplier_name]
      end
    end
    json.last_prices(@purchase[:last_prices]) do |lp|
      json.name lp[:name]
      json.code lp[:code]
      json.this_rate_micros lp[:this_rate_micros]
      json.rate_micros lp[:rate_micros]
      json.price_tax_included lp[:price_tax_included]
      json.supplier_name lp[:supplier_name]
      json.po_no lp[:po_no]
      json.ordered_at lp[:ordered_at]
    end
  end
end
