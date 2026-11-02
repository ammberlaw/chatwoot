json.id resource.id
json.crm_product_id resource.crm_product_id
json.sku resource.crm_product&.sku
json.name resource.crm_product&.name
json.specification resource.crm_product&.specification
json.unit resource.crm_product&.unit
json.unit_price_micros resource.unit_price_micros
json.remark resource.remark
json.updated_by_name resource.updated_by&.name
json.updated_at resource.updated_at

# 这颗料最近一次真实成交（已审核采购单）。标准价旁边摆一份成交价，
# 才看得出这条标准价还作不作数——口径见 MaterialPricesController#recent_purchase_marks。
mark = local_assigns[:last_purchase]
if mark
  json.last_purchase do
    json.rate_micros mark[:rate_micros]
    json.price_tax_included mark[:price_tax_included]
    json.supplier_name mark[:supplier_name]
    json.po_no mark[:po_no]
    json.ordered_at mark[:ordered_at]
    json.times mark[:times]
    json.supplier_count mark[:supplier_count]
  end
else
  json.last_purchase nil
end
