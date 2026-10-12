# 一张生产订单领用原料花了多少钱（领料减退料）。
#
# 口径：**逐料**取「实际 FIFO 消耗」，批次层没覆盖到的那部分按最近一次采购单价兜底。
#
# ⚠️ 必须逐料算，不能「整单只要有一条消耗记录就全走 FIFO」：上 FIFO 核算之前备的库存
# 没有批次层，领出去时扣不到层、一条消耗记录也不产生。整单口径会把这些料当成 0 成本
# 直接漏掉——成本算少、毛利虚高，而且不报错。过渡期（原料期初批次导入之前）每张单都是
# 「一部分有层、一部分没层」，正是这个洞最容易踩到的时候。
class Erp::MaterialIssueCost
  ISSUE_PURPOSE = 'MATERIAL_ISSUE'.freeze
  RETURN_PURPOSE = 'MATERIAL_RETURN'.freeze

  def initialize(account)
    @account = account
  end

  def net_amount(production_order)
    (issue_amount(production_order) - return_amount(production_order)).round
  end

  private

  def issue_amount(order)
    consumed = fifo_consumed_by_key(order)
    qty_by_key(order, ISSUE_PURPOSE).sum do |(key, info)|
      hit = consumed[key]
      next info[:qty] * last_purchase_price(*info[:ids]) if hit.nil?

      uncovered = [info[:qty] - hit[:qty], 0].max
      hit[:amount] + (uncovered * last_purchase_price(*info[:ids]))
    end
  end

  # 退料按**与领料同一个单价口径**冲减：有 FIFO 消耗的用消耗均价，没有的用最近采购价。
  # 两边口径不一样的话，领 100 退 100 会凭空剩下一笔差额。
  def return_amount(order)
    consumed = fifo_consumed_by_key(order)
    qty_by_key(order, RETURN_PURPOSE).sum do |(key, info)|
      hit = consumed[key]
      unit = hit && hit[:qty].positive? ? hit[:amount] / hit[:qty] : last_purchase_price(*info[:ids])
      info[:qty] * unit
    end
  end

  # 某个用途下每颗料的合计领用量。按料归并后再计价——同一颗料分几张单领时，
  # 逐行算会把 FIFO 消耗重复减。ids 留着给兜底查最近采购价用。
  def qty_by_key(order, purpose)
    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(account_id: @account.id)
      .where(mes_stock_entries: { production_order_id: order.id, purpose: purpose, status: 'POSTED' })
      .pluck(:mes_material_id, :crm_product_id, :qty, :received_qty)
      .each_with_object({}) do |(material_id, product_id, qty, received_qty), out|
        key = item_key(material_id, product_id) or next

        row = (out[key] ||= { qty: 0.to_d, ids: [material_id, product_id] })
        row[:qty] += (received_qty.presence || qty).to_d
      end
  end

  # 这张订单已记在册的 FIFO 消耗：每颗料扣了多少量、多少钱。
  def fifo_consumed_by_key(order)
    @fifo_consumed ||= {}
    @fifo_consumed[order.id] ||=
      @account.erp_stock_consumptions
              .joins(:stock_entry)
              .where(mes_stock_entries: { production_order_id: order.id,
                                          purpose: ISSUE_PURPOSE, status: 'POSTED' })
              .pluck(:mes_material_id, :crm_product_id, :qty, :base_amount_micros)
              .each_with_object({}) do |(material_id, product_id, qty, amount), out|
                key = item_key(material_id, product_id) or next

                row = (out[key] ||= { qty: 0.to_d, amount: 0.to_d })
                row[:qty] += qty.to_d
                row[:amount] += amount.to_d
              end
  end

  # 一颗料的归并键：挂物料档就按物料，否则按商品档。两种挂法都有，不归一会把同一颗料当成两个。
  def item_key(material_id, product_id)
    return "m#{material_id}" if material_id.present?

    product_id && "p#{product_id}"
  end

  # 最近一次采购单价（兜底）。草稿与已取消的单不算，与外协口径一致。
  def last_purchase_price(material_id, product_id)
    return 0 if material_id.blank? && product_id.blank?

    @last_prices ||= {}
    @last_prices[[material_id, product_id]] ||= begin
      scope = Mes::PurchaseItem.joins(:purchase_order)
                               .where(account_id: @account.id)
                               .where(mes_purchase_orders: { status: Erp::CostRollupService::COUNTED_PO_STATUSES })
                               .where('mes_purchase_items.rate_micros > 0')
      scope = material_id.present? ? scope.where(mes_material_id: material_id) : scope.where(crm_product_id: product_id)
      scope.order('mes_purchase_orders.created_at DESC').pick(:rate_micros).to_i
    end
  end
end
