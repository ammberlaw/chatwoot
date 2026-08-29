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
