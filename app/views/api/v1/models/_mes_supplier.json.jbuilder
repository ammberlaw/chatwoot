json.id resource.id
json.supplier_no resource.supplier_no
json.name resource.name
json.contact_name resource.contact_name
json.phone resource.phone
json.email resource.email
json.address resource.address
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
json.is_active resource.is_active
json.remark resource.remark
json.product_line resource.product_line
json.department resource.department
json.category resource.category
# 供应商开票/银行/税号 + 采购单价属采购口径，销售端不可见（生态硬约束）——仅 MES 员工。
mes_staff = Current.account_user&.mes_staff?
if mes_staff
  json.tax_rate resource.tax_rate
  json.invoice_title resource.invoice_title
  json.tax_no resource.tax_no
  json.bill_entity resource.bill_entity
  json.bank_name resource.bank_name
  json.bank_account resource.bank_account
  json.bank_address resource.bank_address
end
json.supplier_items resource.supplier_items.sort_by(&:id) do |item|
  json.id item.id
  json.material_code item.material_code
  json.category item.category
  json.name item.name
  json.color item.color
  json.specification item.specification
  json.unit item.unit
  if mes_staff
    json.unit_price item.unit_price
    json.unit_price_taxed item.unit_price_taxed
  end
  json.mes_material_id item.mes_material_id
end
json.created_at resource.created_at
json.updated_at resource.updated_at
