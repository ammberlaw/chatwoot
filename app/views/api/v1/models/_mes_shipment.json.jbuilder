json.id resource.id
json.shipment_no resource.shipment_no
json.crm_sales_order_id resource.crm_sales_order_id
json.sales_order_no resource.crm_sales_order&.order_no
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.warehouse_id resource.warehouse_id
json.status resource.status
json.notified_at resource.notified_at
json.shipped_at resource.shipped_at
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
json.shipment_items do
  json.array! resource.shipment_items.order(:id) do |item|
    json.id item.id
    json.crm_product_id item.crm_product_id
    json.product_name item.crm_product&.name
    json.qty item.qty
    json.unit item.unit
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
