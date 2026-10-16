# 这张生产订单「组装齐了没有 / 包装齐了没有」。
#
# 用户原话：「对应的订单添加一个组装齐和包装齐的按键，方便业务看。」
# 业务要的是在销售订单列表上一眼看出能不能开工、能不能装箱，而不是点进缺料清单一张张数。
#
# 口径：BOM 行按类别分两组（MACHINE 整机料 → 组装，PACKAGING 包装料 → 包装），
#   需求量 = BOM 行用量 × 订单量 / 基准量
#   到料量 = 挂本单的未关闭采购单里同一颗料的 received_qty 合计
# 两边都按**产品档案**归集，和算料页（ProductionOrder#material_requirements）、
# 缺料清单（Mes::KitShortage）走同一套对法——口径一走偏就会出现「清单说齐了、徽标说没齐」。
#
# 列表一次几十张单，所以只提供批量入口：逐张展开 BOM 是上千条 SQL。
class Mes::KitReadiness
  CATEGORIES = { machine: 'MACHINE', packaging: 'PACKAGING' }.freeze

  # { order_id => { machine: { ready:, short: }, packaging: { ready:, short: } } }
  # 没挂 BOM / 基准量为 0 / 该类别一行料都没有 → ready 给 nil（＝不知道，前端不显示徽标），
  # 不能当成「齐了」：料都还没定出来就标齐套，业务会照着它去催发货。
  def self.bulk(account, orders)
    orders = orders.to_a
    return {} if orders.empty?

    new(account, orders).call
  end

  def initialize(account, orders)
    @account = account
    @orders = orders.select { |o| o.bom_id.present? }
  end

  def call
    return {} if @orders.empty?

    rows = bom_rows
    product_ids = product_id_map(rows)
    received = received_qty_map
    @orders.to_h { |order| [order.id, state_for(order, rows[order.bom_id], product_ids, received[order.id])] }
  end

  private

  def state_for(order, rows, product_ids, received)
    factor = order.bom&.base_qty.to_d.zero? ? 0 : order.qty.to_d / order.bom.base_qty.to_d
    CATEGORIES.transform_values do |category|
      group_state(rows.to_a.select { |r| r[2] == category }, factor, product_ids, received || {})
    end
  end

  def group_state(rows, factor, product_ids, received)
    return { ready: nil, short: nil } if rows.empty? || factor.zero?

    short = rows.count { |(material_no, qty, _)| short_row?(product_ids[material_no], received, qty.to_d * factor) }
    { ready: short.zero?, short: short }
  end

  # 对不上产品档案的行（料号没建档）一律算「没到」：宁可显示没齐，也不能糊过去。
  def short_row?(crm_product_id, received, required)
    crm_product_id.blank? || (received[crm_product_id] || 0).to_d < required
  end

  # { bom_id => [[material_no, qty, category], ...] }
  def bom_rows
    Mes::BomItem.where(bom_id: @orders.map(&:bom_id))
                .pluck(:bom_id, :material_no, :qty, :category)
                .group_by(&:first)
                .transform_values { |rows| rows.map { |r| [r[1], r[2], r[3]] } }
  end

  def product_id_map(rows)
    codes = rows.values.flatten(1).filter_map(&:first).uniq
    return {} if codes.empty?

    Crm::Product.where(account_id: @account.id, sku: codes).pluck(:sku, :id).to_h
  end

  # { order_id => { crm_product_id => 已到料量 } }。关闭的采购单不算（它的货不会来了）。
  def received_qty_map
    Mes::PurchaseItem
      .joins(:purchase_order)
      .where(mes_purchase_orders: { production_order_id: @orders.map(&:id) })
      .where.not(mes_purchase_orders: { status: 'CANCELLED' })
      .where.not(crm_product_id: nil)
      .group('mes_purchase_orders.production_order_id', :crm_product_id)
      .sum(:received_qty)
      .each_with_object({}) { |((order_id, pid), sum), acc| (acc[order_id] ||= {})[pid] = sum }
  end
end
