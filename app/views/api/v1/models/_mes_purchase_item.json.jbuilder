json.id resource.id
json.item_type resource.item_type
json.mes_material_id resource.mes_material_id
json.material_name resource.mes_material&.name
json.material_no resource.mes_material&.material_no
json.specification resource.mes_material&.specification || resource.crm_product&.specification
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.product_sku resource.crm_product&.sku
# 供应商属采购口径，**销售端**不可见（生态硬约束）。但财务要按供应商对账、采购审批人
# 要知道这单发给谁，都得看得到——原来只认 mes_staff?，把财务一起挡在外面了，
# 「按明细」视图里供应商整列是「—」。口径与金额那条一致（见 _mes_purchase_order）。
if Current.account_user&.mes_staff? ||
   Current.account_user&.crm_finance? ||
   Mes::PurchaseOrder.approver?(Current.account, Current.user&.id)
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
# 未税 / 含税各摆一列：录入口径按行不同（price_tax_included），只给一个「单价」
# 分不清是哪种，跟供应商对账就对不上。
json.untaxed_rate_micros can_view_amount ? resource.untaxed_rate_micros : nil
json.taxed_rate_micros can_view_amount ? resource.taxed_rate_micros : nil
json.untaxed_amount_micros can_view_amount ? resource.untaxed_amount_micros : nil
json.taxed_amount_micros can_view_amount ? resource.taxed_amount_micros : nil
json.received_qty resource.received_qty
# 辅助属性快照（算料时从生产任务单带出）+ 产品档案备注，导出给供应商的采购单要印。
json.aux_attribute_name resource.aux_attribute_name
json.product_remark resource.crm_product&.remark
json.remark resource.remark
# 行内附图（只对内）。带上 signed_id：前端提交时要把「这一行当前应有的全部图」原样回传，
# 后端 images= 是整组替换语义——少传一张就等于删一张。
json.images resource.images.map { |f|
  { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true), signed_id: f.blob.signed_id }
}
# 跟这颗料上次买多少比（只给看得到金额的人，见父单据）。
json.price_benchmark local_assigns[:price_benchmark]
