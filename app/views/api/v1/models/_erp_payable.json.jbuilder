json.id resource.id
json.payable_no resource.payable_no
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.mes_purchase_order_id resource.mes_purchase_order_id
# 这家供应商的那张单号（PU-20260928-04-01）——财务对账认的就是供应商手上那张单的号。
json.po_no(resource.mes_purchase_order &&
           Mes::PoSupplierNumber.for(resource.mes_purchase_order, resource.mes_supplier_id))
json.currency resource.currency
json.exchange_rate resource.exchange_rate
json.total_amount_micros resource.total_amount_micros
json.paid_amount_micros resource.paid_amount_micros
json.outstanding_micros resource.outstanding_micros
json.status resource.status
json.status_label Erp::Payable::STATUS_LABELS[resource.status]
json.due_date resource.due_date
json.settle_type resource.settle_type
json.settle_type_label Erp::Payable::SETTLE_TYPE_LABELS[resource.settle_type]
# 发生日期＝货到那天。没入库过的单回落到建账日——与台账筛选、按月未付用的是同一个口径
# （控制器 INCURRED_ON_SQL），不然按日期筛出来的行，这一列却是空的。
json.incurred_on(resource.incurred_on || resource.created_at.to_date)
json.remark resource.remark

# 采购明细直接摊在台账上（物料编码/品名/规格/数量/单价/金额）——财务要核「这笔钱买了什么、什么价」，
# 以前只有供应商和采购单号，得点进采购单一张张看。只取这张采购单里属于本供应商的行。
json.line_items(resource.supplier_items) do |item|
  json.code item.crm_product&.sku.presence || item.mes_material&.material_no
  json.name item.crm_product&.name.presence || item.mes_material&.name
  json.spec item.mes_material&.specification.presence || item.crm_product&.specification
  json.unit item.unit
  json.quantity item.qty
  json.received_qty item.received_qty
  json.unit_price_micros item.rate_micros
  json.amount_micros item.amount_micros
  json.price_tax_included item.price_tax_included
  json.remark item.remark
end
