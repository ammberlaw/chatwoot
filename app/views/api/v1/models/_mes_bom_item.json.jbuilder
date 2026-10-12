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
# 成本（仅财务/管理员/采购）：单价由 Mes::MaterialPriceResolver 按
# 本单采购价 > 标准价 > 最近采购价 三级取，父 BOM 批量算好经 local 传入。
# 取不到价的行这三个键都是 nil——前端据此标「无单价」，不要渲染成 0。
price = local_assigns[:price_map]&.dig(resource.id)
json.unit_price_micros price&.dig(:price_micros)
json.price_source price&.dig(:source)
json.price_source_label price&.dig(:source_label)
# 价源是「多单价不一」时，把每张生产订单各买了多少钱带出来——
# 不然财务只看到一个数，不知道这颗料在本任务单里其实有两三个价。
json.price_breakdown price&.dig(:breakdown)
json.amount_micros(price ? (resource.qty.to_d * price[:price_micros]).round : nil)

json.remark resource.remark
# 采购注意事项给采购看（建采购单时按料带过去，但不进给供应商的导出件）；
# 生产备注只给公司内部生产部门看，不进任何对外单据。
json.purchase_note resource.purchase_note
json.production_note resource.production_note
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
