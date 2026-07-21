json.payload do
  json.array! @balances do |b|
    json.id b.id
    json.item_type b.item_type
    json.mes_material_id b.mes_material_id
    json.material_name b.mes_material&.name
    json.material_no b.mes_material&.material_no
    json.crm_product_id b.crm_product_id
    json.product_name b.crm_product&.name
    json.warehouse_id b.warehouse_id
    json.warehouse_name b.warehouse&.name
    json.qty b.qty
    json.unit b.mes_material&.unit
    json.safety_stock b.mes_material&.safety_stock
    json.is_short b.short?
  end
end
