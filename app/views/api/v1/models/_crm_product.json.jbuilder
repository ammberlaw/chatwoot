json.id resource.id
json.name resource.name
json.sku resource.sku
json.category resource.category
json.source_category resource.source_category
json.product_line resource.product_line
json.specification resource.specification
json.unit resource.unit
# 成本价属采购/财务口径，销售端不可见（生态硬约束）——仅管理员/财务/MES 员工可读。
if Current.account_user&.crm_finance? || Current.account_user&.mes_staff?
  json.cost_price_micros resource.cost_price_micros
end
json.sale_price_micros resource.sale_price_micros
json.pricing_currency resource.pricing_currency
json.is_active resource.is_active
json.remark resource.remark
json.group_code resource.group_code
json.updated_at resource.updated_at
# 辅助属性（启用中）：选完物料，明细行的「辅助属性」下拉直接有选项，不用再跑一趟接口。
json.aux_attributes do
  json.array! resource.aux_attributes.active.ordered do |attribute|
    json.partial! 'api/v1/models/crm_product_aux_attribute', formats: [:json], resource: attribute
  end
end
