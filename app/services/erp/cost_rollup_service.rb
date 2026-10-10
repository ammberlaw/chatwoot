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
# 自产单在材料之外还归集两项（外协单不归：加工费已经含在对方报价里了，再加一遍就重复）：
#     生产人工  LABOR    = 完工入库数量 × BOM 成本表的加工费
#     制造费用  OVERHEAD = 完工入库数量 × BOM 成本表的制造费用
#   数量取**已过账的成品入库**（MANUFACTURE），不是下单量——没做出来的不该摊成本。
#   商品编码在 BOM 成本表里没维护就记 0，跟物料没成本价时一个处理方式：宁可少算不编数。
#
# 幂等：一张生产订单**每种成本口径**一条行（source_type='Mes::ProductionOrder' + cost_type），
# 重复归集只更新金额，不会翻倍；某项算出来是 0 就删掉那条行（如全部退料、加工费没维护）。
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
    production_orders_of(sales_order.id).flat_map { |order| sync_production_order(order) }
  end

  # 批量归集（补历史）：可按销售订单下单日期圈范围。返回 { synced:, skipped: }。
  def rollup_all(from: nil, to: nil)
    scope = @account.crm_sales_orders.dealt
    scope = scope.where(order_date: from..) if from.present?
    scope = scope.where(order_date: ..to) if to.present?

    synced = 0
    orders = production_orders_of(scope.select(:id))
    # 空数组是 truthy，不能直接 if——按真正写进去的行数算
    orders.each { |order| synced += 1 if sync_production_order(order).any? }
    { synced: synced, scanned: orders.size }
  end

  # 单张生产订单归集。返回写入的成本行数组（可能 0~3 条）。
  def sync_production_order(production_order)
    return [] if production_order.crm_sales_order_id.blank?

    amounts = amounts_for(production_order)
    existing = existing_rows(production_order)

    # 本轮算出来是 0 的口径要把旧行清掉：否则改了数量/退了料，旧金额会一直赖着。
    (existing.keys - amounts.keys).each { |t| existing[t].destroy! }

    amounts.filter_map do |cost_type, amount|
      if amount <= 0
        existing[cost_type]&.destroy!
        next
      end

      write_row(existing[cost_type], production_order, amount, cost_type)
    end
  end

  # 该生产订单的**材料**成本（本位币 micros）。FIFO 给自产成品定价时复用：
  # 成品单位成本 = 本方法 ÷ 完工入库数量。
  #
  # ⚠️ 故意只含材料（外协单则是采购额），不含人工/制造费用：人工是按**完工入库数量**算的，
  # 而本方法正是在成品入库过账、给存货层定价时被调用的，把它算进来就成了自己引用自己。
  # 存货估值要不要含加工成本是另一个口径问题，等财务明确再说。
  def production_cost_micros(production_order)
    if production_order.is_outsourced
      outsource_amount(production_order)
    else
      material_amount(production_order)
    end
  end

  private

  def production_orders_of(sales_order_ids)
    @account.mes_production_orders
            .where(crm_sales_order_id: sales_order_ids)
            .where.not(status: 'CANCELLED')
            .to_a
  end

  # 该生产订单已归集的行，按成本口径索引。
  def existing_rows(production_order)
    @account.erp_order_costs
            .where(source_type: SOURCE_TYPE, source_id: production_order.id)
            .index_by(&:cost_type)
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

  # 返回 { 成本类型 => 金额micros }。外协只有一项，自产三项。
  def amounts_for(production_order)
    return { 'PROCESS' => outsource_amount(production_order) } if production_order.is_outsourced

    done_qty = finished_qty(production_order)
    std = bom_cost_for(production_order)
    {
      'MATERIAL' => material_amount(production_order),
      'LABOR' => (done_qty * std[:process]).round,
      'OVERHEAD' => (done_qty * std[:overhead]).round
    }
  end

  # 已过账的成品入库数量（实收优先，没填实收取应收）。
  FINISH_PURPOSE = 'MANUFACTURE'.freeze

  def finished_qty(production_order)
    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(account_id: @account.id)
      .where(mes_stock_entries: { production_order_id: production_order.id,
                                  purpose: FINISH_PURPOSE, status: 'POSTED' })
      .pluck(:qty, :received_qty)
      .sum { |qty, received| (received.presence || qty).to_d }
  end

  # 本单成品在 BOM 成本表里的单价。没挂商品编码、或表里没这条，都按 0——
  # 少算看得见（毛利页成本偏低），编数看不见。
  def bom_cost_for(production_order)
    pid = production_order.crm_product_id
    return { process: 0, overhead: 0 } if pid.blank?

    @bom_costs ||= @account.erp_bom_costs.index_by(&:crm_product_id)
    row = @bom_costs[pid]
    { process: row&.process_fee_micros.to_i, overhead: row&.overhead_fee_micros.to_i }
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

  # 自产：已过账的领料减退料，按**最近一次采购单价**计价。
  #
  # 不走物料档/商品档的成本价：这两张档的 cost_price_micros 生产上一条都没维护
  # （物料档 2789 条全空），取出来恒等于 0。采购单上的单价是真实付过钱的数。
  #
  # 领料明细挂 mes_material_id 还是 crm_product_id 都认：生产端把屏、主板这些料
  # 建在商品档里（sku 以 M./O. 开头），只认 mes_material_id 会漏掉绝大多数行。
  #
  # 某颗料从没采购过（或采购单没填价）就按 0 计——宁可少算也不编数，差额财务在
  # 成本页看得见、可手工补一条。
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
           .pluck(:mes_material_id, :crm_product_id, :qty, :received_qty)
    return 0 if rows.empty?

    rows.sum do |material_id, product_id, qty, received_qty|
      effective = (received_qty.presence || qty).to_d
      effective * last_purchase_price(material_id, product_id)
    end
  end

  # 最近一次采购单价。草稿与已取消的单不算，与外协口径一致（COUNTED_PO_STATUSES）。
  # 整轮归集里按料缓存：一张领料单几十行，不缓存会把同一颗料查几十遍。
  def last_purchase_price(material_id, product_id)
    return 0 if material_id.blank? && product_id.blank?

    @last_purchase_prices ||= {}
    @last_purchase_prices[[material_id, product_id]] ||= begin
      scope = Mes::PurchaseItem.joins(:purchase_order)
                               .where(account_id: @account.id)
                               .where(mes_purchase_orders: { status: COUNTED_PO_STATUSES })
                               .where('mes_purchase_items.rate_micros > 0')
      scope = material_id.present? ? scope.where(mes_material_id: material_id) : scope.where(crm_product_id: product_id)
      scope.order('mes_purchase_orders.created_at DESC').pick(:rate_micros).to_i
    end
  end
end
