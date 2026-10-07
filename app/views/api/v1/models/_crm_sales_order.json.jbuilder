json.id resource.id
json.name resource.name
json.order_no resource.order_no
json.pi_no resource.pi_no
# 明细原样下发，另外把编码(sku)解析出来——明细里只存了 crm_product_id，
# 前端没法从 id 显示编码（@product_sku_by_id 由控制器批量预载）。
json.line_items(Array(resource.line_items).map do |item|
  next item unless item.is_a?(Hash)

  item.merge('sku' => @product_sku_by_id&.[](item['crm_product_id'].presence&.to_i))
end)
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.customer_country resource.crm_customer&.trade_country

# PI 抬头信息：订单与 PI 之间没有外键，只能按 pi_no 对（控制器已批量预载成 @pi_by_no）。
# 对不上就整块为 nil——生产上 488 张订单只有 106 张对得上，前端必须按「没有」渲染。
pi = @pi_by_no&.[](resource.pi_no)
json.pi_info do
  if pi
    json.buyer_company pi.buyer_company
    json.buyer_address pi.buyer_address
    json.buyer_email pi.buyer_email
    json.buyer_tel pi.buyer_tel
    json.buyer_eori pi.buyer_eori
    json.port_of_shipment pi.port_of_shipment
    json.port_of_destination pi.port_of_destination
    json.country_of_origin pi.country_of_origin
    json.shipping_method pi.shipping_method
  else
    json.nil!
  end
end
json.contact_id resource.contact_id
json.crm_opportunity_id resource.crm_opportunity_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_display_name
json.owner_avatar_url resource.owner&.avatar_url
json.handled_by_id resource.handled_by_id
json.handled_by_name resource.handled_by&.crm_display_name
json.status resource.status
json.order_kind resource.order_kind
json.order_date resource.order_date
json.delivery_date resource.delivery_date
json.order_currency resource.order_currency
json.exchange_rate resource.exchange_rate
json.tax_rate resource.tax_rate
json.amount_includes_tax resource.amount_includes_tax
json.order_amount_micros resource.order_amount_micros
json.shipping_micros resource.shipping_micros
# 成本 / 毛利只发给管钱的角色：管理员、副管理员、财务。
# 销售端绝不可见是公司硬规矩，只靠前端不渲染挡不住——业务员拿自己的 token
# curl 一下就全看见了，所以在序列化这层就不下发。
# ⚠️ 部门主管(crm_manager)也在排除之列，是业务上明确要求的，别当成漏配加回来。
if (au = Current.account_user) && (au.administrator? || au.crm_deputy_admin? || au.crm_finance?)
  json.cost_amount_micros resource.cost_amount_micros
  json.profit_amount_micros resource.profit_amount_micros
  json.profit_rate resource.profit_rate
end
json.remark resource.remark
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f) } }
json.created_at resource.created_at
json.updated_at resource.updated_at
