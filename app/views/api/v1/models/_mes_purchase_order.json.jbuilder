json.id resource.id
json.po_no resource.po_no
json.supplier_names resource.purchase_items.filter_map { |i| i.mes_supplier&.name }.uniq
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.production_order_owner_name resource.production_order&.owner&.name
json.status resource.status
json.approval_status resource.approval_status
json.submitted_at resource.submitted_at
json.gm_id resource.gm_id
json.gm_name resource.gm&.name
json.gm_acted_at resource.gm_acted_at
json.gm_comment resource.gm_comment
json.current_approver_id resource.current_approver_id
json.expected_date resource.expected_date
json.follow_up_date resource.follow_up_date
json.delivery_date resource.delivery_date
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
json.partial! 'api/v1/models/mes_return_state', formats: [:json], resource: resource
json.created_at resource.created_at
json.updated_at resource.updated_at
