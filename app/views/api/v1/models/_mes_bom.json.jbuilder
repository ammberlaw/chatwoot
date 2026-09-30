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
json.owner_name mes_staff_name(resource.owner, Mes::StaffNames::ENGINEERING)
json.sales_owner_id resource.sales_owner_id
json.sales_owner_name mes_staff_name(resource.sales_owner)
json.remark resource.remark
json.images resource.images.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true) } }
onhand_map = resource.onhand_by_material_no
product_map = resource.product_info_by_material_no
json.bom_items do
  json.array! resource.bom_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_bom_item', formats: [:json], resource: item,
                  onhand_map: onhand_map, product_map: product_map
  end
end
json.revisions do
  json.array! resource.bom_revisions do |rev|
    json.id rev.id
    json.rev_no rev.rev_no
    json.reason rev.reason
    json.diff rev.diff
    json.changed_by_name mes_staff_name(rev.changed_by, Mes::StaffNames::ENGINEERING)
    json.created_at rev.created_at
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
