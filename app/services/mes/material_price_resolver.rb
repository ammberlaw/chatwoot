# 给生产任务单的每行用料配一个单价，并说清这个价是哪来的。
#
# 财务要算任务单的产品单价，原来得导出任务单再去采购单里一颗颗查。这个服务把查价
# 这步做掉，并且**标出每个价的来源**——因为覆盖率不可能是 100%，一个不标来源的
# 合计数会让人误以为它是全的。
#
# 三级优先级：
#   ORDER    本单采购价   —— 这张任务单名下生产订单自己的采购单（草稿/作废不算）。真金白银，最准。
#   MIXED    多单价不一   —— 同一颗料在本任务单的几张生产订单里买价不同（备货期涨跌价很常见）。
#                            这时没有唯一正确的单价，取最近一张并**标出来**，附每张单各是多少。
#   STANDARD 标准价       —— 物料单价表（财务/采购维护）。没为这单下过采购单时用。
#   RECENT   最近采购价   —— 这颗料最后一次有价的采购，兜底参考。
#   nil      无价         —— 三级都没有，留空不填 0。
#
# 用料行按「代码」(material_no) 记料，它就是商品档的 sku；个别行也可能直接挂了
# mes_material_id。两种都认，统一归一成一个 key 再查价。
class Mes::MaterialPriceResolver
  ORDER = 'ORDER'.freeze
  MIXED = 'MIXED'.freeze
  STANDARD = 'STANDARD'.freeze
  RECENT = 'RECENT'.freeze

  SOURCE_LABELS = {
    ORDER => '本单采购',
    MIXED => '多单价不一',
    STANDARD => '标准价',
    RECENT => '最近采购'
  }.freeze

  # 与外协归集同一口径：草稿和已取消的采购单不作数。
  COUNTED_PO_STATUSES = %w[SUBMITTED PARTIAL_RECEIVED RECEIVED].freeze

  # items: 实现 material_no / mes_material_id 的对象集合（Mes::BomItem）
  # production_orders: 这张任务单名下的生产订单（可多张）。有就启用「本单采购价」这一级。
  #
  # ⚠️ 一张生产任务单经常挂好几张生产订单（同一个机型分批下单），各自的采购价还可能不同
  #    （备货期涨跌价）。原来这里只取第一张，于是任务单上显示的成本按第一批的价算，
  #    后面几批的价全被忽略——这就是「同一个物料订单单价不一样，取错了」。
  def initialize(account:, items:, production_orders: nil)
    @account = account
    @items = items.to_a
    @production_order_ids = Array(production_orders).compact.map(&:id)
  end

  # => { bom_item_id => { price_micros:, source:, source_label: } }，无价的行不出现在结果里
  def perform
    return {} if @items.empty?

    @items.each_with_object({}) do |item, out|
      key = key_for(item)
      next if key.nil?

      price, source = lookup(key)
      next if price.to_i <= 0

      out[item.id] = { price_micros: price, source: source, source_label: SOURCE_LABELS[source],
                       # 价格不一致时把每张生产订单各是多少带出去，财务才知道该认哪一张。
                       breakdown: source == MIXED ? order_breakdown[key] : nil }
    end
  end

  private

  # 用料行挂物料档就用物料 id，否则按代码落到商品档；两边都归一成同一种 key，
  # 免得同一颗料因为挂法不同被当成两个东西。
  def key_for(item)
    return "m#{item.mes_material_id}" if item.mes_material_id.present?

    pid = product_ids[item.material_no.to_s.strip]
    pid && "p#{pid}"
  end

  def product_ids
    @product_ids ||= @account.crm_products
                             .where(sku: @items.filter_map { |i| i.material_no.presence })
                             .pluck(:sku, :id).to_h
  end

  def lookup(key)
    if order_prices[key]
      # 同一颗料在本任务单的几张生产订单里买价不同 → 取最近一张，但标成「多单价不一」。
      mixed = order_breakdown[key].to_a.pluck(:price_micros).uniq.size > 1
      return [order_prices[key], mixed ? MIXED : ORDER]
    end
    return [standard_prices[key], STANDARD] if standard_prices[key]
    return [recent_prices[key], RECENT] if recent_prices[key]

    [nil, nil]
  end

  # 本单采购价：这张任务单名下**所有**生产订单的采购明细。同一颗料下过几张单就取最后一张
  # （改过价的以最新为准）；几张单价格不一致的，由 lookup 标成 MIXED 并附明细。
  def order_prices
    @order_prices ||= index_by_key(order_rows.map { |r| r.values_at(0, 1, 2) })
  end

  # [[material_id, product_id, rate_micros, 生产订单号], ...]，按时间升序。
  def order_rows
    return @order_rows if defined?(@order_rows)
    return @order_rows = [] if @production_order_ids.empty?

    @order_rows = purchase_scope
                  .joins('INNER JOIN mes_production_orders ' \
                         'ON mes_production_orders.id = mes_purchase_orders.production_order_id')
                  .where(mes_purchase_orders: { production_order_id: @production_order_ids })
                  .order('mes_purchase_orders.created_at ASC')
                  .pluck(:mes_material_id, :crm_product_id, :rate_micros,
                         'mes_production_orders.order_no')
  end

  # { key => [{ order_no:, price_micros: }] }：每颗料在哪张生产订单上买了多少钱。
  def order_breakdown
    @order_breakdown ||= order_rows.each_with_object({}) do |(material_id, product_id, rate, order_no), out|
      key = material_id.present? ? "m#{material_id}" : (product_id && "p#{product_id}")
      next if key.nil?

      (out[key] ||= []) << { order_no: order_no, price_micros: rate }
    end
  end

  # 标准价与「最近采购价」都是全局的，与具体哪张单无关：列表页一页 25 行会
  # 各建一个 resolver，不共享就是 25 次全表扫。挂在 Current 上按请求缓存一次。
  def catalog
    Current.material_price_catalog ||= {}
    Current.material_price_catalog[@account.id] ||= build_catalog
  end

  def build_catalog
    { standard: @account.mes_material_prices
                        .where('unit_price_micros > 0')
                        .pluck(:crm_product_id, :unit_price_micros)
                        .to_h
                        .transform_keys { |pid| "p#{pid}" },
      recent: index_by_key(
        purchase_scope.order('mes_purchase_orders.created_at ASC')
                      .pluck(:mes_material_id, :crm_product_id, :rate_micros)
      ) }
  end

  def standard_prices = catalog[:standard]
  def recent_prices = catalog[:recent]

  # ⚠️ 这个 scope 同时供全局「最近采购价」用，**不能** join 生产订单：
  # inner join 会把没挂生产订单的采购单整批漏掉，兜底价直接少一大截。
  # 要生产订单号的地方（order_rows）自己再 join。
  def purchase_scope
    Mes::PurchaseItem.joins(:purchase_order)
                     .where(account_id: @account.id)
                     .where(mes_purchase_orders: { status: COUNTED_PO_STATUSES })
                     .where('mes_purchase_items.rate_micros > 0')
  end

  # 按时间升序喂进来，后写的覆盖先写的 → 留下的是最新那条。
  def index_by_key(rows)
    rows.each_with_object({}) do |(material_id, product_id, rate), out|
      key = material_id.present? ? "m#{material_id}" : (product_id && "p#{product_id}")
      out[key] = rate if key
    end
  end
end
