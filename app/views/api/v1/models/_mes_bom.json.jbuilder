json.id resource.id
json.bom_no resource.bom_no
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.base_qty resource.base_qty
json.unit resource.unit
json.submit_date resource.submit_date
json.doc_no resource.doc_no
json.customer_name resource.customer_name
json.model resource.model
json.product_code resource.product_code
json.order_qty resource.order_qty
json.bare_color resource.bare_color
json.case_color resource.case_color
json.estimated_lead_days resource.estimated_lead_days
json.purchasing_days resource.purchasing_days
json.material_inbound_days resource.material_inbound_days
json.picking_days resource.picking_days
json.production_days resource.production_days
json.fg_inbound_days resource.fg_inbound_days
json.total_lead_days resource.total_lead_days
json.product_line resource.product_line
json.status resource.status
json.is_active resource.is_active
json.is_default resource.is_default
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
json.bom_items do
  json.array! resource.bom_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_bom_item', formats: [:json], resource: item
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
