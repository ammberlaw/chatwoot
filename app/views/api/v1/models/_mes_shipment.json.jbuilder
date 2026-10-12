json.id resource.id
json.shipment_no resource.shipment_no
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name mes_staff_name(resource.production_order&.owner)
json.warehouse_id resource.warehouse_id
json.kind resource.kind
json.status resource.status
json.notified_at resource.notified_at
json.submitted_at resource.submitted_at
json.approved_at resource.approved_at
json.manager_id resource.manager_id
json.manager_name mes_staff_name(resource.manager)
json.reject_reason resource.reject_reason
json.shipped_at resource.shipped_at
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::WAREHOUSE)
json.remark resource.remark
# 发货仓 + 客户地址：销售出库单票面上要印「发货仓库」和「交货地点」，
# 原来这两样只能点进别处看。
json.warehouse_name resource.warehouse&.name
json.customer_address resource.crm_customer&.address
json.sales_order_remark resource.crm_sales_order&.remark
# 销售单价按订单明细里同一个产品那行取（出库单自己不存价）。
# 这是卖给客户的价，不是成本，销售端本来就看得到。
order_lines = resource.crm_sales_order&.line_item_rows.to_a
json.shipment_items do
  json.array! resource.shipment_items.order(:id) do |item|
    line = order_lines.find { |r| r[:sku].present? && r[:sku] == item.crm_product&.sku }
    json.id item.id
    json.crm_product_id item.crm_product_id
    json.product_name item.crm_product&.name
    json.product_sku item.crm_product&.sku
    json.specification item.crm_product&.specification
    json.qty item.qty
    json.unit item.unit
    json.unit_price line&.dig(:unit_price)
    # 金额按**本次出库量**算，不是订单量——出库单上的钱是这一车货的钱。
    json.amount(line&.dig(:unit_price) ? (item.qty.to_d * line[:unit_price].to_d) : nil)
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
