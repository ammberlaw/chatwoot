# 一颗料「现在有多少是真能给这张工单用的」。
#
# 为什么不能直接拿结存当「有料」：实查生产上 34 张在产工单涉及 441 种料，其中 133 种
# 被两张以上工单同时要（P.12.3000 被 15 张单要、合计 22000）。库存 5000 的料，
# 15 张单各要 1000~3000，按结存判就是**每张单都显示齐了、于是谁都不下单**。
#
# 原材料没有「预占」字段——系统里的预占只对成品，由现货出库单「提交即预占」产生
# （Mes::Shipment.reserved_qty_map）。原材料真正占着货的，是其他在产工单还没领走的
# 那部分需求。所以这里把它算出来，当成原材料的预占。
#
# 分配规则：按交期先后排队，早交期的单先占，晚的单看剩多少。没填交期的排最后
# （不能排最前：没交期的单往往是还没谈定的，不该把货先占走）。
class Mes::MaterialAvailability
  # { 工单id => { 产品档案id => { pending: 还要领, available: 这张单分到的可用库存 } } }
  def self.for(account, orders)
    new(account, orders).call
  end

  def initialize(account, orders)
    @account = account
    # 只有在产且挂了 BOM 的单才会占料。
    @orders = orders.to_a.select { |o| o.status == 'IN_PROGRESS' && o.bom_id.present? }
  end

  def call
    return {} if @orders.empty?

    remaining = on_hand_map.dup
    # 两轮分配。
    # 第一轮：每张单先把「为它自己买回来、还没领走」的那部分拿走——采购单是挂在工单上的，
    # 这是一笔明确的指定分配，不能被别的单按交期抢走。实测漏了这轮就会出事：
    # MO-20260924-03 为自己买了 1000 颗 P.09.001 且已到货，但它没填交期排在最后，
    # 结果只分到 783，徽标从「齐」变成「没齐」。
    claimed = queue.to_h { |order| [order.id, claim_own(order, remaining)] }
    # 第二轮：剩下的公共库存按交期排队分，早交期的先占。
    queue.to_h { |order| [order.id, take_for(order, remaining, claimed[order.id])] }
  end

  # 本单采购已到货、还没被领走的那部分，优先归本单。
  def claim_own(order, remaining)
    received = own_received_map[order.id] || {}
    issued = issued_map[order.id] || {}
    pending_map(order).to_h do |pid, pending|
      mine = [received[pid].to_d - issued[pid].to_d, 0.to_d].max
      take = [pending, mine, remaining[pid].to_d].min
      take = 0.to_d if take.negative?
      remaining[pid] = remaining[pid].to_d - take
      [pid, take]
    end
  end

  private

  # 交期早的先占；没交期的排最后（用一个必然最大的日期占位）。
  FAR_FUTURE = Date.new(9999, 1, 1)

  def queue
    @queue ||= all_open_orders.sort_by { |o| [o.delivery_date&.to_date || FAR_FUTURE, o.id] }
  end

  # 排队要把**全部**在产工单算进来，不能只算调用方传进来的那几张：
  # 列表分页一次只给 25 张，只按这 25 张排队会把别的单占的货算成可用。
  def all_open_orders
    @all_open_orders ||= @account.mes_production_orders
                                 .where(status: 'IN_PROGRESS').where.not(bom_id: nil)
                                 .includes(bom: :bom_items).to_a
  end

  # 轮到这张单时，它能从剩下的库存里拿走多少；拿走的从 remaining 里扣掉。
  # 不在调用方关心范围内的单也要走一遍扣减（它们确实占着货），只是不返回结果。
  def take_for(order, remaining, mine)
    pending_map(order).to_h do |pid, pending|
      own = mine[pid].to_d
      left = remaining[pid].to_d
      take = (pending - own).clamp(0.to_d, [left, 0.to_d].max)
      remaining[pid] = left - take
      [pid, { pending: pending, available: own + take }]
    end
  end

  # 这张单每颗料「还要领多少」＝ 需求 − 已领（已领的货早就出库了，不再占结存）。
  def pending_map(order)
    base = order.bom&.base_qty.to_d
    return {} if base.zero?

    accumulate_pending(order.bom.bom_items.reject(&:blocked?),
                       order.qty.to_d / base, issued_map[order.id] || {})
  end

  def accumulate_pending(items, factor, issued)
    items.each_with_object({}) do |item, acc|
      pid = product_ids[item.material_no]
      next if pid.blank?

      pending = [(item.qty.to_d * factor) - issued[pid].to_d, 0.to_d].max
      acc[pid] = (acc[pid] || 0.to_d) + pending
    end
  end

  def product_ids
    @product_ids ||= begin
      nos = all_open_orders.flat_map { |o| o.bom&.bom_items.to_a.map(&:material_no) }.compact.uniq
      nos.empty? ? {} : @account.crm_products.where(sku: nos).pluck(:sku, :id).to_h
    end
  end

  # 各单已领量（已过账的领料单）：{ 工单id => { 产品档案id => 已领 } }
  def issued_map
    @issued_map ||= Mes::StockEntryItem
                    .joins(:stock_entry)
                    .where(mes_stock_entries: { production_order_id: all_open_orders.map(&:id),
                                                purpose: 'MATERIAL_ISSUE', status: 'POSTED' })
                    .where.not(crm_product_id: nil)
                    .group('mes_stock_entries.production_order_id', 'mes_stock_entry_items.crm_product_id')
                    .sum('mes_stock_entry_items.qty')
                    .each_with_object({}) { |((oid, pid), qty), acc| (acc[oid] ||= {})[pid] = qty }
  end

  # 各单「为自己买回来的已到货量」：{ 工单id => { 产品档案id => 到货 } }。
  # 关闭/作废的采购单不算（它的货不会来了）。
  def own_received_map
    @own_received_map ||= Mes::PurchaseItem
                          .joins(:purchase_order)
                          .where(mes_purchase_orders: { production_order_id: all_open_orders.map(&:id) })
                          .where.not(mes_purchase_orders: { status: 'CANCELLED' })
                          .where.not(crm_product_id: nil)
                          .group('mes_purchase_orders.production_order_id', 'mes_purchase_items.crm_product_id')
                          .sum('mes_purchase_items.received_qty')
                          .each_with_object({}) { |((oid, pid), qty), acc| (acc[oid] ||= {})[pid] = qty }
  end

  def on_hand_map
    ids = product_ids.values
    return {} if ids.empty?

    Mes::StockBalance.where(account_id: @account.id, crm_product_id: ids)
                     .group(:crm_product_id).sum(:qty)
  end
end
