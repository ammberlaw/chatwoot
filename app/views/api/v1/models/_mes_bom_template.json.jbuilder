json.id resource.id
json.name resource.name
json.base_qty resource.base_qty
json.unit resource.unit
json.purchasing_days resource.purchasing_days
json.material_inbound_days resource.material_inbound_days
json.picking_days resource.picking_days
json.production_days resource.production_days
json.fg_inbound_days resource.fg_inbound_days
json.product_line resource.product_line
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.remark resource.remark
json.items_count resource.bom_template_items.size
json.bom_template_items do
  json.array! resource.bom_template_items.order(:id) do |item|
    json.partial! 'api/v1/models/mes_bom_template_item', formats: [:json], resource: item
  end
end
json.created_at resource.created_at
json.updated_at resource.updated_at
