json.id resource.id
json.return_no resource.return_no
json.status resource.status
json.status_label resource.status_label
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.product_line resource.product_line
json.sent_on resource.sent_on
json.returned_on resource.returned_on
# 退出去多少天了（还没回来就是到今天为止）——用户要的就是这个数。
json.days_out resource.days_out
json.out resource.out?
json.reason resource.reason
json.remark resource.remark
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner)
json.items do
  json.array! resource.items.order(:id) do |item|
    json.id item.id
    json.crm_product_id item.crm_product_id
    json.product_sku item.crm_product&.sku
    json.product_name item.crm_product&.name
    json.specification item.crm_product&.specification
    json.qty item.qty
    json.returned_qty item.returned_qty
    json.outstanding_qty item.outstanding_qty
    json.unit item.unit
    json.remark item.remark
  end
end
json.created_at resource.created_at
