# 应付「按月未付」：行 = 供应商 × 结算方式（含税/未税），列 = 各月未付货款，末列 = 期末未付合计。
# 回答财务那句「截止到 8 月底，还欠哪些供应商各多少钱，对公对私分开，具体欠的是哪几个月的货」。
#
# 口径：
#   · 截止日 as_of 之前发生的应付才算（incurred_on = 货到那天，不是财务录单那天）；
#   · 已付只认 as_of 之前付出去的款——8 月底的欠款不能被 9 月付的钱冲掉；
#   · 一笔应付的未付额整笔算在它发生的那个月，不跨月摊；
#   · 金额一律折本位币（台账存原币，外币直接相加＝把美元当人民币）。
class Erp::PayableMonthlyService
  # 往前铺多少个月。再早的并进「更早」一列——列太多表就没法看了。
  DEFAULT_MONTHS = 12

  Row = Struct.new(:supplier_id, :supplier_name, :settle_type, :by_month, :total_micros, keyword_init: true)

  def initialize(account:, as_of: nil, months: DEFAULT_MONTHS, supplier_id: nil)
    @account = account
    @as_of = as_of.presence ? Date.parse(as_of.to_s).end_of_month : Date.current.end_of_month
    @months = months.to_i.clamp(1, 36)
    @supplier_id = supplier_id.presence
  end

  def call
    { as_of: @as_of, months: month_keys, earlier_key: EARLIER, rows: rows, totals: totals }
  end

  EARLIER = 'earlier'.freeze

  private

  def month_keys
    @month_keys ||= (0...@months).map { |i| (@as_of << i).strftime('%Y-%m') }.reverse
  end

  def first_month_start
    @first_month_start ||= (@as_of << (@months - 1)).beginning_of_month
  end

  # 截至 as_of 发生的应付；incurred_on 没填的老单回落到建账日期。
  def payables
    scope = @account.erp_payables
                    .where('COALESCE(erp_payables.incurred_on, erp_payables.created_at::date) <= ?', @as_of)
    scope = scope.where(mes_supplier_id: @supplier_id) if @supplier_id
    scope.includes(:mes_supplier)
  end

  # 截至 as_of 已核销出去的金额，按应付逐笔汇总（作废的付款单不算）。
  def paid_by_payable
    @paid_by_payable ||= Erp::PaymentAllocation
                         .joins(:payment_record)
                         .where(account_id: @account.id)
                         .where(erp_payment_records: { status: Erp::PaymentRecord::NORMAL })
                         .where('erp_payment_records.paid_at <= ?', @as_of)
                         .group(:payable_id)
                         .sum(:amount_micros)
  end

  def rows
    @rows ||= build_rows.sort_by { |row| [-row.total_micros, row.supplier_name.to_s] }
  end

  def build_rows
    buckets = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    names = {}
    payables.find_each do |payable|
      outstanding = outstanding_base_micros(payable)
      next if outstanding <= 0

      key = [payable.mes_supplier_id, payable.settle_type]
      names[key] = payable.mes_supplier&.name
      buckets[key][month_key_for(payable)] += outstanding
    end
    buckets.map do |(supplier_id, settle_type), by_month|
      Row.new(supplier_id: supplier_id, supplier_name: names[[supplier_id, settle_type]],
              settle_type: settle_type, by_month: by_month, total_micros: by_month.values.sum)
    end
  end

  # 原币未付额折本位币。先在原币上扣已付，再乘汇率——顺序反了会按今天的汇率折昨天的付款。
  def outstanding_base_micros(payable)
    outstanding = payable.total_amount_micros.to_i - paid_by_payable[payable.id].to_i
    return 0 if outstanding <= 0

    (outstanding * (payable.exchange_rate || 1)).round
  end

  def month_key_for(payable)
    date = payable.incurred_on || payable.created_at.to_date
    date < first_month_start ? EARLIER : date.strftime('%Y-%m')
  end

  def totals
    sums = Hash.new(0)
    rows.each { |row| row.by_month.each { |month, micros| sums[month] += micros } }
    sums['total'] = sums.values.sum
    sums
  end
end
