json.id resource.id
json.po_no resource.po_no
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name resource.production_order&.owner&.name
json.status resource.status
json.expected_date resource.expected_date
json.follow_up_date resource.follow_up_date
json.has_exception resource.has_exception
json.exception_note resource.exception_note
json.total_amount_micros resource.total_amount_micros
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
json.purchase_items do
  json.array! resource.purchase_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_purchase_item', formats: [:json], resource: item
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
