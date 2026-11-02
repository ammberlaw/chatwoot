json.id resource.id
json.order_no resource.order_no
json.status resource.status
json.doc_date resource.doc_date
json.delivery_date resource.delivery_date
json.product_line resource.product_line
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.crm_product_id resource.crm_product_id
json.product_name resource.crm_product&.name
json.product_sku resource.crm_product&.sku
json.qty resource.qty
json.unit resource.unit
json.mes_warehouse_id resource.mes_warehouse_id
json.outsource_warehouse_name resource.mes_warehouse&.name
json.to_warehouse_id resource.to_warehouse_id
json.to_warehouse_name resource.to_warehouse&.name
# 加工费按件计价：存一个价 + 一个「含不含税」的标志，两头都吐出去省得前端再算。
json.fee_rate_micros resource.fee_rate_micros
json.fee_tax_included resource.fee_tax_included
json.tax_rate resource.tax_rate
json.fee_rate_untaxed_micros resource.fee_rate_untaxed_micros
json.fee_rate_taxed_micros resource.fee_rate_taxed_micros
json.owner_name mes_staff_name(resource.owner)
json.remark resource.remark
json.created_at resource.created_at

# 进度：收了多少、还差多少。列表上一眼看出哪张单还在加工厂手上。
json.received_qty resource.received_qty
json.remaining_qty resource.remaining_qty

# 这张加工单派生的三张单。发料/入库/退料生成的是**草稿**，要在加工单上看得到、
# 点得了过账——否则单据生成完就没了去处（它们不在原料入库那几个页面的 purpose 里）。
json.stock_entries resource.stock_entries.order(created_at: :desc) do |entry|
  json.id entry.id
  json.entry_no entry.entry_no
  json.purpose entry.purpose
  json.status entry.status
  json.posted_at entry.posted_at
  json.created_at entry.created_at
  json.from_warehouse_id entry.from_warehouse_id
  json.to_warehouse_id entry.to_warehouse_id
  # 产品入库单上「数量」只能是**产出台数**。它的明细里还挂着按标准用量倒冲的料行，
  # 全加起来是「40 台 + 40.8 片 + 80 片 = 160.8」这种没有量纲的数，仓管和财务
  # 看了会当成入库了 160 台（2026-11-02 验到）。倒冲行数另给一个字段，界面上
  # 写成「20（倒冲 9 行）」，和发料/退料的「450（9 行）」区分开。
  product_items, material_items = entry.stock_entry_items.partition { |i| i.item_type == 'PRODUCT' }
  receipt = entry.purpose == 'OUTSOURCE_RECEIPT'
  json.total_qty((receipt ? product_items : entry.stock_entry_items).sum(&:qty))
  json.line_count((receipt ? product_items : entry.stock_entry_items).size)
  json.backflush_line_count(receipt ? material_items.size : 0)
end

json.outsource_materials resource.outsource_materials do |material|
  json.id material.id
  json.mes_material_id material.mes_material_id
  json.crm_product_id material.crm_product_id
  json.item_code material.item_code
  json.item_name material.display_name
  json.unit material.unit
  json.qty_numerator material.qty_numerator
  json.qty_denominator material.qty_denominator
  json.loss_rate material.loss_rate
  json.std_qty material.std_qty
  json.from_warehouse_id material.from_warehouse_id
  json.remark material.remark
  # 已发 / 已耗（倒冲）/ 已退 / 还能退——退料单上那几栏就是这些数
  json.issued_qty resource.issued_qty_for(material)
  json.backflushed_qty resource.backflushed_qty_for(material)
  json.returned_qty resource.returned_qty_for(material)
  json.returnable_qty resource.returnable_qty_for(material)
end
