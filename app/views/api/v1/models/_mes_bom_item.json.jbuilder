json.id resource.id
json.mes_material_id resource.mes_material_id
json.material_no resource.material_no
json.material_name resource.material_name
json.category resource.category
json.specification resource.specification
json.qty resource.qty
json.unit resource.unit
json.suggested_purchase_qty resource.suggested_purchase_qty
# 对应物料实时库存（料号↔产品档案 SKU 匹配汇总）；父 BOM 批量算好经 local 传入，避免逐行查库。
json.on_hand(local_assigns[:onhand_map] ? (local_assigns[:onhand_map][resource.material_no] || 0) : nil)
json.remark resource.remark
json.crm_product_aux_attribute_id resource.crm_product_aux_attribute_id
json.aux_attribute_name resource.aux_attribute_name
# 产品档案带过来的两样（按料号↔SKU 对上）：工程写在档案上的备注、以及该物料的辅助属性选项。
product = local_assigns[:product_map]&.dig(resource.material_no)
json.product_remark product&.remark
json.aux_options do
  json.array!(product&.aux_attributes&.select(&:is_active)&.sort_by { |a| [a.position.to_i, a.id] } || []) do |attribute|
    json.partial! 'api/v1/models/crm_product_aux_attribute', formats: [:json], resource: attribute
  end
end
