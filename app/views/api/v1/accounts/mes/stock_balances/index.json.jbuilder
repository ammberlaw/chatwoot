json.payload do
  json.array! @balances do |b|
    json.id b.id
    json.item_type b.item_type
    json.mes_material_id b.mes_material_id
    json.material_name b.mes_material&.name
    json.material_no b.mes_material&.material_no
    json.crm_product_id b.crm_product_id
    json.product_name b.crm_product&.name
    # 编码/规格：MES 的库存实际按产品档案记，列表要能按编码找货、按规格认货。
    json.sku b.crm_product&.sku || b.mes_material&.material_no
    json.specification b.crm_product&.specification
    json.warehouse_id b.warehouse_id
    json.warehouse_name b.warehouse&.name
    json.qty b.qty
    reserved = b.item_type == 'PRODUCT' ? (@reserved[[b.crm_product_id, b.warehouse_id]] || 0) : 0
    json.reserved_qty reserved
    json.available_qty b.qty.to_d - reserved.to_d
    # 物料主数据基本没用上（库存按产品档案走），单位回落到产品档案，否则整列都是空。
    json.unit b.mes_material&.unit || b.crm_product&.unit
    json.safety_stock b.mes_material&.safety_stock
    json.is_short b.short?
  end
end
