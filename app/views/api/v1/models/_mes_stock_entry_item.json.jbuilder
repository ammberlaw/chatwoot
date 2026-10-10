json.id resource.id
json.item_type resource.item_type
json.mes_material_id resource.mes_material_id
json.material_name resource.mes_material&.name
json.material_no resource.mes_material&.material_no
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.qty resource.qty
json.received_qty resource.received_qty
json.unit resource.unit
json.warehouse_id resource.warehouse_id
json.remark resource.remark
# 行内附图（只对内）。带上 signed_id：前端提交时要把「这一行当前应有的全部图」原样回传，
# 后端 images= 是整组替换语义——少传一张就等于删一张。
json.images resource.images.map { |f|
  { id: f.id, filename: f.filename.to_s, url: rails_blob_path(f, only_path: true), signed_id: f.blob.signed_id }
}
