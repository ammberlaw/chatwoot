json.id resource.id
json.return_no resource.return_no
json.status resource.status
json.status_label resource.status_label
json.mes_supplier_id resource.mes_supplier_id
json.supplier_name resource.mes_supplier&.name
json.production_order_id resource.production_order_id
json.production_order_no resource.production_order&.order_no
json.product_line resource.product_line
json.sent_on resource.sent_on
json.returned_on resource.returned_on
# 退出去多少天了（还没回来就是到今天为止）——用户要的就是这个数。
json.days_out resource.days_out
json.out resource.out?
json.reason resource.reason
json.remark resource.remark
json.owner_id resource.owner_id
json.owner_name mes_staff_name(resource.owner)
# 退法：换新的只扣库存，不要了连采购和应付一起冲（见 Mes::SupplierReturn::RETURN_KINDS）。
json.return_kind resource.return_kind
json.return_kind_label resource.return_kind_label
json.warehouse_id resource.warehouse_id
json.warehouse_name resource.warehouse&.name
# 关联单号三样：货是哪张采购单买的、哪张入库单收的、退出去生成了哪张出库单。
json.purchase_order_id resource.mes_purchase_order_id
json.purchase_order_no resource.mes_purchase_order&.po_no
json.source_entry_no resource.source_stock_entry&.entry_no
# 来源单据可能是原料入库单，也可能是车间的生产退料单（不良品就是这么进不良品仓的），
# 带上 purpose 让界面分得清，别让财务以为这批货是采购收进来的。
json.source_entry_kind resource.source_stock_entry&.purpose
json.out_entry_no resource.out_stock_entry&.entry_no
json.total_amount_micros resource.items.sum { |i| (i.unit_price_micros.to_i * i.qty.to_d).round }

# 「库存」列：这颗料此刻在**退料那个仓**还有多少。退的就是那儿的货，
# 不摆出来的话填数量时只能凭记忆，填超了要等过账才被拦。
# 一次查完整单的料，别在循环里逐行查（一张单十几行就是十几次往返）。
stock_by_product =
  if resource.warehouse_id
    resource.account.mes_stock_balances
            .where(warehouse_id: resource.warehouse_id, item_type: 'MATERIAL',
                   crm_product_id: resource.items.map(&:crm_product_id).compact)
            .pluck(:crm_product_id, :qty).to_h
  else
    {}
  end
json.items do
  json.array! resource.items.order(:id) do |item|
    json.id item.id
    json.crm_product_id item.crm_product_id
    json.product_sku item.crm_product&.sku
    json.product_name item.crm_product&.name
    json.specification item.crm_product&.specification
    json.qty item.qty
    json.returned_qty item.returned_qty
    json.outstanding_qty item.outstanding_qty
    json.unit item.unit
    # 价格默认从关联采购单那颗料的单价带出来，也允许手改——退货价和采购价不一定一样。
    json.unit_price_micros item.unit_price_micros
    json.amount_micros (item.unit_price_micros.to_i * item.qty.to_d).round
    json.stock_qty stock_by_product[item.crm_product_id]
    json.remark item.remark
  end
end
json.created_at resource.created_at
