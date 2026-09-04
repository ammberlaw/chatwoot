json.id resource.id
json.item_type resource.item_type
json.mes_material_id resource.mes_material_id
json.crm_product_id resource.crm_product_id
json.material_no resource.material_no.presence || resource.mes_material&.material_no
json.material_name resource.material_name.presence || resource.mes_material&.name || resource.crm_product&.name
json.specification resource.specification.presence || resource.mes_material&.specification
json.unit resource.unit
# 供应商属采购口径，销售端不可见（生态硬约束）——仅 MES 员工。
if Current.account_user&.mes_staff?
  json.mes_supplier_id resource.mes_supplier_id
  json.supplier_name resource.mes_supplier&.name
end
json.required_qty resource.required_qty
json.suggested_qty resource.suggested_qty
json.ordered_qty resource.ordered_qty
json.remaining_qty resource.remaining_qty
json.remark resource.remark
