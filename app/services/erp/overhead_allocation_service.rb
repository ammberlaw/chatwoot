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
    rows = finished_rows(from, to)
    qty = rows.sum { |r| r[:qty] }
    rate = qty.positive? ? (total / qty) : 0
    {
      period: period, overhead_micros: total, finished_qty: qty,
      rate_micros: rate.round,
      # 末位订单吸收舍入差，保证各单相加严格等于总额——差一分钱财务就要来问。
      rows: with_rounding_fix(rows, rate, total)
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

  def upsert_cost(row, period)
    order = @account.mes_production_orders.find_by(id: row[:production_order_id])
    return if order.nil? || order.crm_sales_order_id.blank?

    cost = @account.erp_order_costs.find_or_initialize_by(
      source_type: SOURCE_TYPE, source_id: order.id, cost_type: COST_TYPE
    )
    # 分摊结果为 0 就把行删掉，别留一条 0 元成本行误导人（同按单归集的处理）。
    return cost.destroy if cost.persisted? && row[:amount_micros].to_i.zero?
    return if row[:amount_micros].to_i.zero?

    cost.update!(crm_sales_order_id: order.crm_sales_order_id,
                 amount_micros: row[:amount_micros], currency: BASE_CURRENCY, exchange_rate: 1,
                 remark: "#{period} 制造费用平均分摊（#{fnum(row[:qty])} 台）")
  end

  def fnum(value)
    d = value.to_d
    d == d.to_i ? d.to_i.to_s : d.to_s('F')
  end
end
