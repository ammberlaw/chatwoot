# 期末结账：把一个会计期间关掉，并把损益结转到本年利润。
#
# 结账前三道闸（任何一道不过就不让关）：
#   1. 该期间不能有待过账凭证——草稿要么过账要么作废，不能挂着；
#   2. 该期间借贷必须试算平衡；
#   3. 期间没被关过。
# 关账后该期间凭证全冻结（Erp::Voucher 的 validate_period_open）。
# 反结账限管理员，删掉结转凭证并留痕（谁在什么时候反的）。
class Erp::PeriodCloseService
  class Error < StandardError; end

  YEAR_PROFIT_TYPE = 'YEAR_PROFIT'.freeze

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  def close!(period)
    validate_period_format!(period)
    record = @account.erp_fiscal_periods.find_or_initialize_by(period: period)
    raise Error, "会计期间 #{period} 已经结过账了" if record.status == Erp::FiscalPeriod::CLOSED

    ensure_earlier_periods_closed!(period)
    ensure_no_drafts!(period)
    ensure_balanced!(period)

    ActiveRecord::Base.transaction do
      voucher = build_closing_voucher(period)
      record.assign_attributes(
        status: Erp::FiscalPeriod::CLOSED, closed_at: Time.current, closed_by_id: @user&.id,
        closing_voucher_id: voucher&.id
      )
      record.save!
    end
    record
  end

  # 反结账：期间重新打开，结转凭证撤销（该凭证是系统生成的，直接删不留垃圾）。
  def reopen!(period)
    record = @account.erp_fiscal_periods.find_by(period: period)
    raise Error, "会计期间 #{period} 没有结过账" if record.blank? || record.status != Erp::FiscalPeriod::CLOSED

    ensure_later_periods_open!(period)
    ensure_year_not_closed!(period)

    ActiveRecord::Base.transaction do
      closing = record.closing_voucher
      record.update!(status: Erp::FiscalPeriod::OPEN, closing_voucher_id: nil,
                     reopened_at: Time.current, reopened_by_id: @user&.id)
      closing&.destroy
    end
    record
  end

  # 期间概览：每月的凭证数、待过账数、借贷合计、结账状态——结账向导那一页要的就是这张表。
  def overview(from_period:, to_period:)
    periods = @account.erp_vouchers.where(period: from_period..to_period).group(:period)
                      .pluck(:period, Arel.sql('COUNT(*)'), Arel.sql("COUNT(*) FILTER (WHERE status = 'DRAFT')"))
    closed = @account.erp_fiscal_periods.where(period: from_period..to_period).index_by(&:period)
    periods.map { |period, total, drafts| overview_row(period, total, drafts, closed[period]) }
           .sort_by { |row| row[:period] }.reverse
  end

  private

  def overview_row(period, total, drafts, fiscal)
    totals = period_totals(period)
    status = fiscal&.status || Erp::FiscalPeriod::OPEN
    {
      period: period, voucher_count: total, draft_count: drafts,
      debit_micros: totals[:debit], credit_micros: totals[:credit],
      balanced: totals[:debit] == totals[:credit],
      checklist: status == Erp::FiscalPeriod::CLOSED ? [] : Erp::PeriodChecklist.new(@account).for(period),
      status: status
    }.merge(closing_info(fiscal))
  end

  def closing_info(fiscal)
    {
      closed_at: fiscal&.closed_at,
      closed_by_name: fiscal&.closed_by&.crm_name.presence || fiscal&.closed_by&.name,
      closing_voucher_no: fiscal&.closing_voucher&.voucher_no
    }
  end

  def validate_period_format!(period)
    raise Error, '会计期间格式应为 YYYY-MM' unless period.to_s.match?(/\A\d{4}-\d{2}\z/)
  end

  # 结账必须**从早到晚**、反结账必须**从晚到早**（金蝶/用友同规矩）。
  #
  # 目前月度结转是各月独立算的，所以跳着结数字还不会错；但「已结账」这三个字的意思是
  # 此前所有期间都封存了——跳着结会出现「4 月已锁、3 月还能随便改」，审计一看就质疑账簿严肃性。
  # 而且**年末结转一旦做起来就是累积的**，那时顺序错就是真的数字错了。
  def ensure_earlier_periods_closed!(period)
    closed = @account.erp_fiscal_periods.where(status: Erp::FiscalPeriod::CLOSED).pluck(:period)
    open_before = @account.erp_vouchers.where(period: ...period).distinct.pluck(:period) - closed
    return if open_before.empty?

    raise Error, "#{open_before.min} 还没结账，会计期间要从早到晚依次结；先结 #{open_before.min}"
  end

  def ensure_later_periods_open!(period)
    later = @account.erp_fiscal_periods.where(status: Erp::FiscalPeriod::CLOSED)
                    .where('period > ?', period).pluck(:period)
    return if later.empty?

    raise Error, "#{later.max} 还锁着，反结账要从晚到早依次做；先反结 #{later.max}"
  end

  # 年结凭证是压在 12 月上的，年结完再去反结该年度任何一个月都会让年结数字失真。
  def ensure_year_not_closed!(period)
    year = period.to_s[0, 4]
    return unless Erp::YearEndCloseService.new(@account).closed?(year)

    raise Error, "#{year} 年度已经年结，要反结账请先反年结"
  end

  def ensure_no_drafts!(period)
    drafts = @account.erp_vouchers.in_period(period).where(status: Erp::Voucher::DRAFT).count
    return if drafts.zero?

    raise Error, "该期间还有 #{drafts} 张待过账凭证，先过账或作废再结账"
  end

  def ensure_balanced!(period)
    totals = period_totals(period)
    return if totals[:debit] == totals[:credit]

    raise Error, "该期间借贷不平（借 #{fmt(totals[:debit])} / 贷 #{fmt(totals[:credit])}），不能结账"
  end

  def period_totals(period)
    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(erp_vouchers: { period: period, status: Erp::Voucher::POSTED })
                   .group(:direction).sum(:base_amount_micros)
    { debit: sums[Erp::VoucherLine::DEBIT].to_i, credit: sums[Erp::VoucherLine::CREDIT].to_i }
  end

  # 结转凭证：把该期末所有损益类科目余额冲平，差额进本年利润。
  # 没有损益发生额就不生成凭证（返回 nil），避免月月挂一张空凭证。
  def build_closing_voucher(period)
    rows = profit_and_loss_rows(period)
    return nil if rows.empty?

    profit_account = @account.erp_ledger_accounts.find_by(account_type: YEAR_PROFIT_TYPE)
    raise Error, '找不到「本年利润」科目（account_type=YEAR_PROFIT），请先在科目表里配置' if profit_account.blank?

    lines = rows + [profit_line(profit_account, rows)]
    create_voucher(period, lines)
  end

  # 每个损益科目按其余额的反方向做一笔，把它冲平。
  def profit_and_loss_rows(period)
    balances = Erp::LedgerQueryService.new(@account).balances(from: period_start(period), to: period_end(period))
    balances.reject { |row| row[:account].is_group? }
            .select { |row| row[:account].category == 'PL' && row[:closing_micros] != 0 }
            .map { |row| closing_line(row) }
  end

  def closing_line(row)
    balance = row[:closing_micros]
    # 余额在借方（费用）就贷记冲平，反之借记。
    debit_side = row[:account].direction == Erp::VoucherLine::DEBIT
    direction = balance.positive? == debit_side ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT
    { ledger_account_id: row[:account].id, direction: direction, amount_micros: balance.abs,
      summary: "期末结转 #{row[:account].name}", currency: 'CNY', exchange_rate: 1 }
  end

  # 本年利润承接差额：损益结转后借贷差多少，本年利润就顶多少。
  def profit_line(profit_account, rows)
    debit = rows.select { |row| row[:direction] == Erp::VoucherLine::DEBIT }.sum { |row| row[:amount_micros] }
    credit = rows.select { |row| row[:direction] == Erp::VoucherLine::CREDIT }.sum { |row| row[:amount_micros] }
    net = debit - credit
    {
      ledger_account_id: profit_account.id,
      direction: net.positive? ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT,
      amount_micros: net.abs, summary: '结转本年利润', currency: 'CNY', exchange_rate: 1
    }
  end

  def create_voucher(period, lines)
    voucher = @account.erp_vouchers.new(
      voucher_date: period_end(period), summary: "#{period} 期末结转损益", status: Erp::Voucher::POSTED,
      prepared_by_id: @user&.id, posted_by_id: @user&.id, posted_at: Time.current,
      source_type: 'Erp::PeriodClose', source_id: nil,
      lines_attributes: lines.each_with_index.map { |row, index| row.merge(position: index) }
    )
    voucher.skip_period_guard = true
    voucher.save!
    voucher.refresh_totals!
    voucher
  end

  def period_start(period)
    Date.parse("#{period}-01")
  end

  def period_end(period)
    period_start(period).end_of_month
  end

  def fmt(micros)
    format('%.2f', micros.to_i / 1_000_000.0)
  end
end
