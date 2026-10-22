json.id resource.id
json.name resource.name
json.order_no resource.order_no
json.pi_no resource.pi_no
# 信保单号 / 收款方式 / 收款账户：录单时的结算信息，原先只能写在备注里、查不了也统计不了。
# payment_term 存的是 crm_option_items 的 code，列表要显示名字（转 ERP 的校验也认这项）。
json.insurance_order_no resource.insurance_order_no
json.payment_term resource.payment_term
json.receipt_account_id resource.receipt_account_id
json.receipt_account_name @cash_account_names&.[](resource.receipt_account_id)
# 明细原样下发，另外把编码(sku)解析出来——明细里只存了 crm_product_id，
# 前端没法从 id 显示编码（@product_sku_by_id 由控制器批量预载）。
json.line_items(Array(resource.line_items).map do |item|
  next item unless item.is_a?(Hash)

  id = item['crm_product_id'].presence&.to_i
  item.merge('sku' => @product_sku_by_id&.[](id), 'product_name' => @product_name_by_id&.[](id))
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
# 审核（与 status 正交）：审过了才能转生产订单/进财务待建账。
json.approval_status resource.approval_status
json.approval_label resource.approval_label
json.approved_by_name resource.approved_by&.name
json.approved_at resource.approved_at
json.reject_reason resource.reject_reason
# 当前这个人能不能审这张单——前端据此决定显不显示「通过/驳回」。
json.can_approve Crm::SalesOrderApprover.can?(Current.account_user, resource)
json.order_kind resource.order_kind
json.delivery_method resource.delivery_method
json.delivery_method_label resource.delivery_method_label
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
