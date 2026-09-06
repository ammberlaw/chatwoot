# 年末结转：把「本年利润」结平到「利润分配—未分配利润」，可选提取法定盈余公积。
#
# **为什么必须有这一步**：月度结账只把损益结转到本年利润(4103)，4103 自己不会归零。
# 不做年结的话 4103 会跨年累加——第二年起资产负债表上的「本年利润」里混着以前年度的利润，
# 「未分配利润」永远是 0，权益结构从第二年开始就不对了（总数仍然平，是分类错）。
#
# 两条设计取舍：
# 1. **年结是单独的动作，不挂在 12 月结账里**（金蝶同款）。年结是一次性重大动作要财务确认；
#    真挂上去，12 月一旦要反结账重来，连带的年结更难收拾。
# 2. **盈余公积按需提**：法定盈余公积 10% 是《公司法》的要求，但提取比例、
#    以及累计已达注册资本 50% 后可不再提，都是判断题。这里做成可填比例，**默认不提**。
#
# 分录（盈利年度）：
#   借 本年利润(4103) / 贷 利润分配(4104)
#   借 利润分配(4104) / 贷 盈余公积(4101)   ← 填了提取比例才有这一笔
# 亏损年度方向相反，且不提盈余公积。
class Erp::YearEndCloseService
  class Error < StandardError; end

  SOURCE_TYPE = 'Erp::YearEndClose'.freeze
  YEAR_PROFIT_TYPE = 'YEAR_PROFIT'.freeze
  RETAINED_CODE = '4104'.freeze  # 利润分配
  SURPLUS_CODE = '4101'.freeze   # 盈余公积

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 预览：不落库。返回该年度本年利润余额、拟提盈余公积、结转后转入未分配利润的数。
  def preview(year:, surplus_rate: 0)
    validate_year!(year)
    profit = year_profit_balance(year)
    surplus = surplus_amount(profit, surplus_rate)
    {
      year: year, as_of: year_end(year),
      profit_micros: profit, surplus_rate: surplus_rate.to_d, surplus_micros: surplus,
      retained_micros: profit - surplus,
      voucher_no: existing_voucher(year)&.voucher_no,
      unclosed_periods: unclosed_periods(year)
    }
  end

  def run!(year:, surplus_rate: 0)
    # 年结级 advisory 锁：并发/重试串行化，配合「已年结即报错」复检，杜绝生成两张年结凭证致本年利润翻倍。
    Erp::AccountLock.with_account_lock(@account.id, "yearend:#{year}") do
      result = preview(year: year, surplus_rate: surplus_rate)
      raise Error, "#{year} 年度已经年结过了（凭证 #{result[:voucher_no]}），要重做请先反年结" if result[:voucher_no].present?
      raise Error, "#{result[:unclosed_periods].join('、')} 还没结账，全年 12 个月都结完才能年结" if result[:unclosed_periods].any?
      raise Error, "#{year} 年度本年利润为 0，没有可结转的数" if result[:profit_micros].zero?

      voucher = build_voucher(result)
      result.merge(voucher_no: voucher.voucher_no)
    end
  end

  # 反年结：撤销年结凭证。年结凭证是系统生成的，直接删不留垃圾（与反结账同做法）。
  def reopen!(year:)
    validate_year!(year)
    voucher = existing_voucher(year)
    raise Error, "#{year} 年度没有年结过" if voucher.blank?

    voucher.destroy
    { year: year, voucher_no: nil }
  end

  # 该年度有没有年结过——反结 12 月之前要先反年结，PeriodCloseService 会问这个。
  def closed?(year)
    existing_voucher(year).present?
  end

  private

  def validate_year!(year)
    raise Error, '年度格式应为 YYYY' unless year.to_s.match?(/\A\d{4}\z/)
  end

  def year_end(year)
    Date.new(year.to_i, 12, 31)
  end

  def existing_voucher(year)
    @account.erp_vouchers.where(source_type: SOURCE_TYPE, period: "#{year}-12").first
  end

  # 全年有凭证、却还没结账的月份。没有凭证的月份不要求结账（空月不用走流程）。
  # ⚠️ 排除年结凭证自身要用 IS DISTINCT FROM：手工凭证的 source_type 是 NULL，
  #    `where.not(source_type: ...)` 在 SQL 里会把 NULL 一起排掉，这道闸就形同虚设了。
  def unclosed_periods(year)
    periods = @account.erp_vouchers.where('period LIKE ?', "#{year}-%")
                      .where('source_type IS DISTINCT FROM ?', SOURCE_TYPE).distinct.pluck(:period)
    closed = @account.erp_fiscal_periods.closed.pluck(:period)
    (periods - closed).sort
  end

  # 本年利润余额（贷方为正＝盈利）。只看该年度，跨年不累计——
  # 上一年度年结后 4103 已归零，所以按「该年度内的发生额」算就是本年利润。
  def year_profit_balance(year)
    profit_account = find_account!(YEAR_PROFIT_TYPE, :type, '本年利润')
    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED,
                                          voucher_date: Date.new(year.to_i, 1, 1)..year_end(year) })
                   .where(ledger_account_id: profit_account.id)
                   .group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::CREDIT].to_i - sums[Erp::VoucherLine::DEBIT].to_i
  end

  # 亏损年度不提盈余公积。
  def surplus_amount(profit, rate)
    return 0 unless profit.positive?

    Erp::VoucherLine.round_to_cent(profit * rate.to_d / 100)
  end

  def find_account!(key, by, label)
    scope = @account.erp_ledger_accounts.active.leaves
    record = by == :type ? scope.find_by(account_type: key) : scope.find_by(code: key)
    raise Error, "找不到「#{label}」科目，请先在科目表里配置" if record.blank?

    record
  end

  def build_voucher(result)
    voucher = @account.erp_vouchers.new(
      voucher_date: result[:as_of], period: "#{result[:year]}-12", status: Erp::Voucher::POSTED,
      summary: "#{result[:year]} 年度结转（本年利润转入未分配利润）",
      prepared_by_id: @user&.id, posted_by_id: @user&.id, posted_at: Time.current,
      source_type: SOURCE_TYPE, lines_attributes: voucher_lines(result)
    )
    # 12 月已结账冻结，年结凭证正是结账之后才做的，跟期末结转凭证一样放行。
    voucher.skip_period_guard = true
    voucher.save!
    voucher.refresh_totals!
    voucher
  end

  def voucher_lines(result)
    profit_account = find_account!(YEAR_PROFIT_TYPE, :type, '本年利润')
    retained = find_account!(RETAINED_CODE, :code, '利润分配')
    profit = result[:profit_micros]
    earning = profit.positive?

    lines = [
      line(profit_account, earning ? Erp::VoucherLine::DEBIT : Erp::VoucherLine::CREDIT, profit.abs, '结转本年利润'),
      line(retained, earning ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT, profit.abs, '转入未分配利润')
    ]
    lines += surplus_lines(retained, result[:surplus_micros]) if result[:surplus_micros].positive?
    lines.each_with_index.map { |row, index| row.merge(position: index) }
  end

  def surplus_lines(retained, amount)
    surplus = find_account!(SURPLUS_CODE, :code, '盈余公积')
    [
      line(retained, Erp::VoucherLine::DEBIT, amount, '提取法定盈余公积'),
      line(surplus, Erp::VoucherLine::CREDIT, amount, '提取法定盈余公积')
    ]
  end

  def line(ledger_account, direction, amount_micros, summary)
    { ledger_account_id: ledger_account.id, direction: direction, amount_micros: amount_micros,
      summary: summary, currency: 'CNY', exchange_rate: 1 }
  end
end
