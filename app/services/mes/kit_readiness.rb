# 这张生产订单「组装齐了没有 / 包装齐了没有」。
#
# 用户原话：「对应的订单添加一个组装齐和包装齐的按键，方便业务看。」
# 业务要的是在销售订单列表上一眼看出能不能开工、能不能装箱，而不是点进缺料清单一张张数。
#
# 口径：BOM 行按类别分两组（MACHINE 整机料 → 组装，PACKAGING 包装料 → 包装）。
#   需求量 = BOM 行用量 × 订单量 / 基准量
#   还要领 = 需求量 − 本单已领
#   可用量 = 库存结存里**分得到这张单头上**的那部分（Mes::MaterialAvailability）
#   齐     ⟺ 还要领 ≤ 可用量（＝这张单的料现在就领得出来）
#
# 2026-10-26 改：原先只比「本单采购单到货量」，库存里现成有的货一概不算。
# 于是库存 5762 的动物卡片、需求 3000，徽标照样报没齐，采购照着去买一批。
# 改成按可用库存判之后，这类行自然变齐，真缺的才留下来。
# ⚠️ 不能直接拿结存判：133 种料被两张以上在产工单同时要，按结存判就是每张单都显示齐了、
# 谁都不下单。分配规则见 Mes::MaterialAvailability（按交期排队，早的先占）。
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
    supply = Mes::MaterialAvailability.for(@account, @orders)
    @orders.to_h { |order| [order.id, state_for(order, rows[order.bom_id], product_ids, supply[order.id] || {})] }
  end

  private

  def state_for(order, rows, product_ids, supply)
    factor = order.bom&.base_qty.to_d.zero? ? 0 : order.qty.to_d / order.bom.base_qty.to_d
    CATEGORIES.transform_values do |category|
      group_state(rows.to_a.select { |r| r[2] == category }, factor, product_ids, supply)
    end
  end

  def group_state(rows, factor, product_ids, supply)
    return { ready: nil, short: nil } if rows.empty? || factor.zero?

    short = rows.count { |(material_no, _qty, _)| short_row?(product_ids[material_no], supply) }
    { ready: short.zero?, short: short }
  end

  # 对不上产品档案的行（料号没建档）一律算「没齐」：宁可显示没齐，也不能糊过去。
  # 建了档的行比「还要领」和「分到的可用量」——领得出来就是齐。
  def short_row?(crm_product_id, supply)
    return true if crm_product_id.blank?

    row = supply[crm_product_id]
    return false if row.nil? # 这颗料不在待领清单里＝已经领完了

    row[:pending].to_d > row[:available].to_d
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
end
