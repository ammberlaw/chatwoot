# 订单成本自动归集：把 MES 里真实发生的耗用/外协采购，算成 erp_order_costs 行。
#
# ⚠️ 口径（关键，防同一批料被计两遍）：
#   为订单专门采购的料，会先「采购收货入库」再「领料出库」。采购单和领料单若都归集，
#   同一批料就被算两遍。所以按生产方式二选一，互不重叠：
#     自产单（is_outsourced=false）→ 按**领料**算材料成本 = Σ(领料 − 退料) × 物料成本价
#     外协单（is_outsourced=true） → 按**采购单**算加工成本 = Σ 采购明细金额
#   自产脊柱里领料是必经环节（MATERIAL_ISSUE 推 PICKING→PRODUCTION），外协脊柱没有领料，
#   两边各自都取得到数，不会漏。
#
# 幂等：一张生产订单一条成本行（source_type='Mes::ProductionOrder'），重复归集只更新金额，
# 不会翻倍；净耗用归零（全部退料）则删掉该行。
# 手工录入的成本行 source_type 为空，本服务**永不改动**——财务补录的运费/佣金不会被冲掉。
class Erp::CostRollupService
  SOURCE_TYPE = 'Mes::ProductionOrder'.freeze

  # MES 采购与物料成本价都是人民币口径（mes_purchase_orders 上没有币种列），
  # 故归集出来的成本行固定本位币，不需要折算。
  BASE_CURRENCY = 'CNY'.freeze

  def initialize(account)
    @account = account
  end

  # 归集一张销售订单下的所有生产订单，返回受影响的成本行数组。
  def for_sales_order(sales_order)
    production_orders_of(sales_order.id).filter_map { |order| sync_production_order(order) }
  end

  # 批量归集（补历史）：可按销售订单下单日期圈范围。返回 { synced:, skipped: }。
  def rollup_all(from: nil, to: nil)
    scope = @account.crm_sales_orders.dealt
    scope = scope.where(order_date: from..) if from.present?
    scope = scope.where(order_date: ..to) if to.present?

    synced = 0
    orders = production_orders_of(scope.select(:id))
    orders.each { |order| synced += 1 if sync_production_order(order) }
    { synced: synced, scanned: orders.size }
  end

  # 单张生产订单归集。返回成本行；净额为 0 时清掉旧行并返回 nil。
  def sync_production_order(production_order)
    return nil if production_order.crm_sales_order_id.blank?

    amount, cost_type = amount_for(production_order)
    existing = existing_row(production_order)

    if amount <= 0
      existing&.destroy!
      return nil
    end

    write_row(existing, production_order, amount, cost_type)
  end

  # 该生产订单的归集成本（本位币 micros）。FIFO 给自产成品定价时复用：
  # 成品单位成本 = 本方法 ÷ 完工入库数量。不另写一套算法，避免两处口径分叉。
  def production_cost_micros(production_order)
    amount_for(production_order).first
  end

  private

  def production_orders_of(sales_order_ids)
    @account.mes_production_orders
            .where(crm_sales_order_id: sales_order_ids)
            .where.not(status: 'CANCELLED')
            .to_a
  end

  def existing_row(production_order)
    @account.erp_order_costs.find_by(source_type: SOURCE_TYPE, source_id: production_order.id)
  end

  def write_row(existing, production_order, amount, cost_type)
    attrs = {
      crm_sales_order_id: production_order.crm_sales_order_id,
      cost_type: cost_type,
      amount_micros: amount,
      currency: BASE_CURRENCY,
      exchange_rate: 1,
      happened_at: Date.current,
      remark: "由生产订单 #{production_order.order_no} 自动归集"
    }
    if existing
      # 归集日期保持首次归集时间，只更新金额与口径。
      existing.update!(attrs.except(:happened_at))
      existing
    else
      @account.erp_order_costs.create!(attrs.merge(source_type: SOURCE_TYPE, source_id: production_order.id))
    end
  end

  # 返回 [金额micros, 成本类型]
  def amount_for(production_order)
    if production_order.is_outsourced
      [outsource_amount(production_order), 'PROCESS']
    else
      [material_amount(production_order), 'MATERIAL']
    end
  end

  # 外协：该生产订单名下已提交/已收货的采购单明细合计（草稿与已取消不算）。
  COUNTED_PO_STATUSES = %w[SUBMITTED PARTIAL_RECEIVED RECEIVED].freeze

  def outsource_amount(production_order)
    Mes::PurchaseItem.joins(:purchase_order)
                     .where(account_id: @account.id)
                     .where(mes_purchase_orders: { production_order_id: production_order.id,
                                                   status: COUNTED_PO_STATUSES })
                     .sum(:amount_micros).to_i
  end

  # 自产：已过账的领料减退料，按物料成本价计价。
  # 物料没维护成本价（cost_price_micros 为空）就当 0 计——宁可少算也不编数，
  # 差额财务在成本页看得见、可手工补一条。
  ISSUE_PURPOSE = 'MATERIAL_ISSUE'.freeze
  RETURN_PURPOSE = 'MATERIAL_RETURN'.freeze

  def material_amount(production_order)
    issued = valued_qty(production_order, ISSUE_PURPOSE)
    returned = valued_qty(production_order, RETURN_PURPOSE)
    (issued - returned).round
  end

  def valued_qty(production_order, purpose)
    rows = Mes::StockEntryItem
           .joins(:stock_entry)
           .where(account_id: @account.id)
           .where(mes_stock_entries: { production_order_id: production_order.id,
                                       purpose: purpose, status: 'POSTED' })
           .pluck(:mes_material_id, :qty, :received_qty)
    return 0 if rows.empty?

    prices = material_prices(rows.filter_map(&:first).uniq)
    rows.sum do |material_id, qty, received_qty|
      effective = (received_qty.presence || qty).to_d
      effective * prices[material_id].to_i
    end
  end

  def material_prices(material_ids)
    return {} if material_ids.empty?

    @account.mes_materials.where(id: material_ids).pluck(:id, :cost_price_micros).to_h
  end
end
