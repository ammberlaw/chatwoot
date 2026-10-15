# 这张生产订单还差哪些料才能齐套开工。
#
# 用户原话：「生产任务单，采购单，原料入库单的整机物料到齐，这张单就可以领料生产了」。
# 系统本来就是这么走的（齐套闸见 Mes::ProductionOrder#purchase_complete?），
# 但订单详情上只有一个「待齐套 3/4」的徽标——差哪几样、差多少、挂在哪张采购单上，
# 车间得找采购一张张点开明细数。这里一次算全。
#
# 口径必须和 Mes::PurchaseOrder#recompute_receipt_status! 一致（同样按 received_qty
# 对 qty 逐行比）。两边一走偏就会出现「单子显示已到货，清单还在列缺料」这种自相矛盾。
class Mes::KitShortage
  # { 采购单id => [{ code:, name:, unit:, qty:, received:, short: }, ...] }
  # 没缺料的采购单不出现在结果里。
  def self.by_purchase_order(purchase_orders)
    purchase_orders.reject { |po| po.status == 'CANCELLED' }
                   .to_h { |po| [po.id, rows_for(po)] }
                   .reject { |_id, rows| rows.empty? }
  end

  def self.rows_for(purchase_order)
    purchase_order.purchase_items.filter_map { |item| row(item) }
  end

  def self.row(item)
    short = item.qty.to_d - item.received_qty.to_d
    return nil unless short.positive?

    # 采购行挂的要么是物料档（原料）要么是产品档（外购成品），两者只会有一个。
    src = item.mes_material || item.crm_product
    { code: src.try(:material_no) || src.try(:sku), name: src&.name,
      unit: item.unit, qty: item.qty, received: item.received_qty, short: short }
  end
  private_class_method :row
end
