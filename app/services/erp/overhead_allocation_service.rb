# 制造费用按月平均分摊到当月完工入库的成品。
#
# 财务口径（2026-10-28 定）：
#     当月单位制造费用 = 当月 5101 制造费用发生额 ÷ 当月完工入库总数量
#     某张生产订单分到 = 该单当月完工入库数量 × 单位制造费用
#
# 为什么不并进 Erp::CostRollupService：那个是**按单**归集、入库就能算；
# 这个是**按月**算的，分母要等当月所有入库都过账、分子要等费用凭证都入完，
# 只能月底跑一次。混在一起会让按单归集每次都去扫全月数据。
#
# 和原来的区别：原来 OVERHEAD = 入库数量 × BOM 成本表里维护的固定值（标准成本），
# 每台永远一样；现在按当月实际发生额摊，当月产量少则每台摊得多。
#
# ⚠️ 取数只认**已过账**的凭证和入库单。没过账的不算数，否则月底一补凭证金额就变了。
class Erp::OverheadAllocationService
  class Error < StandardError; end

  OVERHEAD_CODE = '5101'.freeze
  COST_TYPE = 'OVERHEAD'.freeze
  SOURCE_TYPE = 'Mes::ProductionOrder'.freeze
  FINISH_PURPOSE = 'MANUFACTURE'.freeze
  BASE_CURRENCY = 'CNY'.freeze

  def initialize(account)
    @account = account
  end

  # 只算不写，给界面预览用：分子、分母、单位费用、每张单摊多少。
  def preview(period)
    from, to = range(period)
    total = overhead_total(from, to)
    # 没挂销售订单的生产订单（备库存单）摊不出去——成本只能挂销售订单，它那份没地方记。
    # 所以连分母都不让它进：留在分母里就是「算了台数却分不到钱」，总额会悄悄少摊一截，
    # 「各单相加＝总额」的保证也跟着破。摊不到的单单独报给界面，别让它无声消失。
    rows, skipped = finished_rows(from, to).partition { |r| sales_order_id(r[:production_order_id]) }
    qty = rows.sum { |r| r[:qty] }
    rate = qty.positive? ? (total / qty) : 0
    {
      period: period, overhead_micros: total, finished_qty: qty,
      rate_micros: rate.round,
      # 末位订单吸收舍入差，保证各单相加严格等于总额——差一分钱财务就要来问。
      rows: with_rounding_fix(rows, rate, total),
      skipped_count: skipped.size, skipped_qty: skipped.sum { |r| r[:qty] }
    }
  end

  # 落成 erp_order_costs 的 OVERHEAD 行（与按单归集同一张表、同一个 source_type，
  # 所以同一张生产订单只会有一条 OVERHEAD，不会和原来的标准成本行并存）。
  def allocate!(period)
    result = preview(period)
    raise Error, "#{period} 没有完工入库，没什么可分摊的" if result[:finished_qty].zero?

    ActiveRecord::Base.transaction do
      result[:rows].each { |row| upsert_cost(row, period) }
    end
    result
  end

  private

  def range(period)
    raise Error, '月份格式应为 YYYY-MM' unless period.to_s.match?(/\A\d{4}-\d{2}\z/)

    from = Date.strptime(period, '%Y-%m').beginning_of_month
    [from, from.end_of_month]
  end

  # 当月 5101 发生额 = 借方 − 贷方。
  # 减贷方是防重复分摊：月末结转会贷记 5101，已经转走的部分不该再摊第二遍。
  def overhead_total(from, to)
    ids = account_ids
    return 0 if ids.empty?

    sums = @account.erp_voucher_lines
                   .joins(:voucher)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: from..to })
                   .where(ledger_account_id: ids)
                   .group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::DEBIT].to_i - sums[Erp::VoucherLine::CREDIT].to_i
  end

  # 5101 及其下级科目（制造费用常挂二级明细：折旧、水电、物料消耗…）。
  def account_ids
    root = @account.erp_ledger_accounts.find_by(code: OVERHEAD_CODE)
    return [] if root.nil?

    @account.erp_ledger_accounts.where("code LIKE ?", "#{OVERHEAD_CODE}%").pluck(:id)
  end

  # 当月完工入库，按生产订单汇总。实收优先、没填取应收（与 CostRollupService 同口径）。
  def finished_rows(from, to)
    Mes::StockEntryItem
      .joins(:stock_entry)
      .where(account_id: @account.id)
      .where(mes_stock_entries: { purpose: FINISH_PURPOSE, status: 'POSTED',
                                  posted_at: from.beginning_of_day..to.end_of_day })
      .where.not(mes_stock_entries: { production_order_id: nil })
      .pluck('mes_stock_entries.production_order_id', :qty, :received_qty)
      .group_by(&:first)
      .map do |order_id, items|
        { production_order_id: order_id,
          qty: items.sum { |(_, qty, received)| (received.presence || qty).to_d } }
      end
      .reject { |r| r[:qty] <= 0 }
      .sort_by { |r| r[:production_order_id] }
  end

  # 逐单按单位费用算，最后一单吃掉舍入差。
  def with_rounding_fix(rows, rate, total)
    return rows if rows.empty?

    allocated = 0
    rows.each_with_index do |row, i|
      amount = i == rows.size - 1 ? total - allocated : (row[:qty] * rate).round
      allocated += amount
      row[:amount_micros] = amount
    end
    rows
  end

  # 一张生产订单只有一条 OVERHEAD 行（唯一索引），但它可能分几个月完工入库。
  # 所以金额按月份累加：本月那一项替换掉，其余月份原样留着。
  def upsert_cost(row, period)
    so_id = sales_order_id(row[:production_order_id])
    return if so_id.nil?

    cost = @account.erp_order_costs.find_or_initialize_by(
      source_type: SOURCE_TYPE, source_id: row[:production_order_id], cost_type: COST_TYPE
    )
    breakdown = merged_breakdown(cost, row, period)
    total = breakdown.values.sum { |v| v['amount_micros'].to_i }

    # 全部月份都摊成 0 就把行删掉，别留一条 0 元成本行误导人（同按单归集的处理）。
    return cost.destroy if cost.persisted? && total.zero?
    return if total.zero?

    cost.update!(crm_sales_order_id: so_id, amount_micros: total,
                 currency: BASE_CURRENCY, exchange_rate: 1,
                 allocation_breakdown: breakdown, remark: breakdown_remark(breakdown))
  end

  # 本月摊成 0 就把该月那一项删掉，不是留个 0——否则备注里会挂一串「2026-09 0.00」。
  def merged_breakdown(cost, row, period)
    breakdown = (cost.allocation_breakdown || {}).dup
    if row[:amount_micros].to_i.zero?
      breakdown.delete(period)
    else
      breakdown[period] = { 'amount_micros' => row[:amount_micros], 'qty' => fnum(row[:qty]) }
    end
    breakdown
  end

  # 「制造费用按月分摊：2026-09 15,000.00（300 台）、2026-10 40,000.00（800 台）」
  def breakdown_remark(breakdown)
    parts = breakdown.sort.map do |period, v|
      yuan = ActiveSupport::NumberHelper.number_to_rounded(v['amount_micros'].to_i / 1_000_000.0,
                                                           precision: 2, delimiter: ',')
      "#{period} #{yuan}（#{v['qty']} 台）"
    end
    "制造费用按月分摊：#{parts.join('、')}"
  end

  # { 生产订单 id => 销售订单 id }，没挂销售订单的取不到。一次查完，别在循环里逐张 find。
  def sales_order_id(production_order_id)
    @sales_order_ids ||= @account.mes_production_orders.where.not(crm_sales_order_id: nil)
                                 .pluck(:id, :crm_sales_order_id).to_h
    @sales_order_ids[production_order_id]
  end

  def fnum(value)
    d = value.to_d
    d == d.to_i ? d.to_i.to_s : d.to_s('F')
  end
end
