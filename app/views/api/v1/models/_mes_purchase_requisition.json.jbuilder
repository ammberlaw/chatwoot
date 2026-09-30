json.id resource.id
json.req_no resource.req_no
json.purpose resource.purpose
json.status resource.status
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.product_name resource.production_order&.product_name
json.product_line resource.product_line
json.expected_date resource.expected_date
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::PURCHASING)
json.remark resource.remark
json.po_count resource.purchase_orders.size
json.requisition_items do
  json.array! resource.requisition_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_purchase_requisition_item', formats: [:json], resource: item
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
