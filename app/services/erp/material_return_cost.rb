# 生产退料回库时这批料按多少钱重新入账。
#
# 按**当初从这张生产订单领出去的加权均价**算：退回来的就是当初领走的那批货，
# 用「最近采购价」会凭空制造一笔成本差（备货期涨跌价时尤其明显）。
# 取不到当初的领料记录（上 FIFO 核算之前领的）才落到最近采购价；再取不到按 0——
# 宁可少算也不编数，存货页上看得见缺口。
class Erp::MaterialReturnCost
  MATERIAL_ISSUE = 'MATERIAL_ISSUE'.freeze

  def initialize(account)
    @account = account
  end

  def for(entry, item)
    rows = issue_consumptions(entry, item)
    qty = rows.sum(:qty).to_d
    return last_purchase_price(item) if qty <= 0

    (rows.sum(:base_amount_micros).to_d / qty).round
  end

  private

  def issue_consumptions(entry, item)
    rows = @account.erp_stock_consumptions
                   .joins(:stock_entry)
                   .where(mes_stock_entries: { production_order_id: entry.production_order_id,
                                               purpose: MATERIAL_ISSUE })
    # 一颗料只走一种挂法：物料档优先，没有才按商品档，两边都匹配会把同一批算两遍。
    return rows.where(mes_material_id: item.mes_material_id) if item.mes_material_id.present?

    rows.where(crm_product_id: item.crm_product_id)
  end

  def last_purchase_price(item)
    scope = Mes::PurchaseItem.joins(:purchase_order)
                             .where(account_id: @account.id)
                             .where(mes_purchase_orders: { status: Erp::CostRollupService::COUNTED_PO_STATUSES })
                             .where('mes_purchase_items.rate_micros > 0')
    scope = if item.mes_material_id.present?
              scope.where(mes_material_id: item.mes_material_id)
            else
              scope.where(crm_product_id: item.crm_product_id)
            end
    scope.order('mes_purchase_orders.created_at DESC').pick(:rate_micros).to_i
  end
end
