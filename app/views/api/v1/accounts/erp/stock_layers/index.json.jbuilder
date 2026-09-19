json.meta do
  json.count @layers_count
  json.current_page params[:page] || 1
  json.qty @summary[:qty]
  json.amount_micros @summary[:amount_micros]
  json.physical_qty @summary[:physical_qty]
  json.diff_qty @summary[:diff_qty]
end
json.payload do
  json.array! @layers do |layer|
    json.id layer.id
    json.crm_product_id layer.crm_product_id
    json.product_name layer.crm_product&.name
    json.product_sku layer.crm_product&.sku
    json.warehouse_id layer.warehouse_id
    json.warehouse_name layer.warehouse&.name
    json.qty_in layer.qty_in
    json.qty_remaining layer.qty_remaining
    json.unit_cost_micros layer.unit_cost_micros
    json.amount_remaining_micros layer.amount_remaining_micros
    json.received_at layer.received_at
    json.source_type layer.source_type
    json.remark layer.remark
  end
end
