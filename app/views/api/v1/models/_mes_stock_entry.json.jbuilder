json.id resource.id
json.entry_no resource.entry_no
json.purpose resource.purpose
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.purchase_order_id resource.purchase_order_id
json.purchase_order_no resource.purchase_order&.po_no
json.from_warehouse_id resource.from_warehouse_id
json.to_warehouse_id resource.to_warehouse_id
json.status resource.status
json.posted_at resource.posted_at
json.is_checked resource.is_checked
json.checked_by_id resource.checked_by_id
json.checked_by_name resource.checked_by&.name
json.received_by_id resource.received_by_id
json.received_by_name resource.received_by&.name
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
json.stock_entry_items do
  json.array! resource.stock_entry_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_stock_entry_item', formats: [:json], resource: item
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
