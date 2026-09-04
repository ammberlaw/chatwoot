json.id resource.id
json.item_type resource.item_type
json.mes_material_id resource.mes_material_id
json.material_name resource.mes_material&.name
json.material_no resource.mes_material&.material_no
json.specification resource.mes_material&.specification || resource.crm_product&.specification
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.product_sku resource.crm_product&.sku
# 供应商属采购口径，销售端不可见（生态硬约束）——仅 MES 员工。
if Current.account_user&.mes_staff?
  json.mes_supplier_id resource.mes_supplier_id
  json.supplier_name resource.mes_supplier&.name
end
json.arrival_date resource.arrival_date
json.qty resource.qty
json.unit resource.unit
can_view_amount = local_assigns.fetch(:can_view_amount, true)
json.rate_micros can_view_amount ? resource.rate_micros : nil
json.price_tax_included resource.price_tax_included
json.supplier_tax_rate resource.supplier_tax_rate
json.amount_micros can_view_amount ? resource.amount_micros : nil
json.received_qty resource.received_qty
json.remark resource.remark
