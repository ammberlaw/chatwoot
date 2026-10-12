json.id resource.id
json.item_type resource.item_type
json.mes_material_id resource.mes_material_id
json.material_name resource.mes_material&.name
# 编码：原料取物料号，外购成品那种行挂的是产品档案，取 SKU——
# 两者都空的话入库单上「物料编码」整列是空的，对不上采购单也对不上金蝶。
json.material_no resource.mes_material&.material_no.presence || resource.crm_product&.sku
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.qty resource.qty
json.received_qty resource.received_qty
json.unit resource.unit
json.warehouse_id resource.warehouse_id
# 规格/供应商/单价/金额由父单据按来源采购行算好传进来（见 _mes_stock_entry）——
# 逐行回查采购单就是一页几十条 SQL。取不到的留 nil，前端按「—」渲染。
meta = local_assigns[:meta] || {}
json.specification meta[:specification]
json.supplier_name meta[:supplier_name]
json.unit_price_micros meta[:unit_price_micros]
json.amount_micros meta[:amount_micros]
json.remark resource.remark
# 行内附图（只对内）。带上 signed_id：前端提交时要把「这一行当前应有的全部图」原样回传，
# 后端 images= 是整组替换语义——少传一张就等于删一张。
json.images resource.images.map { |f|
  { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true), signed_id: f.blob.signed_id }
}
