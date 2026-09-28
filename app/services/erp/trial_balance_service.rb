# 科目级汇总表：科目余额表 / 试算平衡表（金蝶「财务报表」里的那两张）。
#
# ⚠️ 与「账簿 → 科目余额表」的区别，别混：
#   账簿那张是查账用的**科目树**，含分类科目的汇总行，点一行钻进明细账；
#   这里两张是**报表**，只列末级科目——分类科目的数是下级汇总上来的，
#   跟着一起进合计就翻倍，试算平衡的「借贷合计相等」立刻对不上。
#
# 试算平衡表把期初/期末余额拆成借贷两栏：按科目自身方向落栏，
# 异常余额（如应收账款出现贷方余额＝预收）落到对侧栏，不写负数——这是金蝶的排法，
# 也是「三对合计各自相等」能成立的前提（借贷记账法下 Σ借 = Σ贷 恒成立，不等就是账坏了）。
#
# 全部实时按 POSTED 凭证算，草稿与作废不进账，金额一律本位币。
class Erp::TrialBalanceService
  # 六个数字列，合计与导出都按这个顺序走。
  TRIAL_COLUMNS = %i[
    opening_debit_micros opening_credit_micros
    debit_micros credit_micros
    closing_debit_micros closing_credit_micros
  ].freeze

  # 三对「必须相等」的合计：列名对 + 给人看的标签。
  BALANCE_PAIRS = [
    { key: 'opening', label: '期初余额', debit: :opening_debit_micros, credit: :opening_credit_micros },
    { key: 'period', label: '本期发生额', debit: :debit_micros, credit: :credit_micros },
    { key: 'closing', label: '期末余额', debit: :closing_debit_micros, credit: :closing_credit_micros }
  ].freeze

  def initialize(account)
    @account = account
    @query = Erp::LedgerQueryService.new(account)
  end

  # 试算平衡表：末级科目的期初借/贷、本期借/贷、期末借/贷，附三对合计与平衡标记。
  def trial_balance(from:, to:)
    rows = leaf_rows(from: from, to: to).map { |row| trial_row(row) }
    totals = TRIAL_COLUMNS.index_with { |key| rows.sum { |row| row[key] } }

    {
      from: from, to: to,
      rows: rows.reject { |row| blank_row?(row) },
      totals: totals,
      checks: BALANCE_PAIRS.map { |pair| check_of(pair, totals) },
      balanced: BALANCE_PAIRS.all? { |pair| totals[pair[:debit]] == totals[pair[:credit]] }
    }
  end

  # 科目余额表：期初余额 / 本期借贷 / 本年累计借贷 / 期末余额（列口径对齐金蝶）。
  # 「本年累计」是账簿那张没有的——财务月度看数要它，故单独再跑一次年初至今的窗口。
  def account_balances(from:, to:)
    ytd = ytd_sums(to)
    rows = leaf_rows(from: from, to: to).map { |row| balance_row(row, ytd) }

    {
      from: from, to: to, ytd_from: year_start(to),
      rows: rows.reject { |row| blank_balance_row?(row) },
      totals: {
        debit_micros: rows.sum { |row| row[:debit_micros] },
        credit_micros: rows.sum { |row| row[:credit_micros] },
        ytd_debit_micros: rows.sum { |row| row[:ytd_debit_micros] },
        ytd_credit_micros: rows.sum { |row| row[:ytd_credit_micros] }
      }
    }
  end

  private

  # 只要末级科目：分类科目的数字是汇总，进了合计就翻倍。
  def leaf_rows(from:, to:)
    @query.balances(from: from, to: to).reject { |row| row[:account].is_group? }
  end

  def trial_row(row)
    account = row[:account]
    opening = split_by_direction(row[:opening_micros], account.direction)
    closing = split_by_direction(row[:closing_micros], account.direction)

    identity(account).merge(
      opening_debit_micros: opening[:debit], opening_credit_micros: opening[:credit],
      debit_micros: row[:debit_micros], credit_micros: row[:credit_micros],
      closing_debit_micros: closing[:debit], closing_credit_micros: closing[:credit]
    )
  end

  def balance_row(row, ytd)
    account = row[:account]
    identity(account).merge(
      opening_micros: row[:opening_micros],
      debit_micros: row[:debit_micros],
      credit_micros: row[:credit_micros],
      ytd_debit_micros: ytd[[account.id, Erp::VoucherLine::DEBIT]].to_i,
      ytd_credit_micros: ytd[[account.id, Erp::VoucherLine::CREDIT]].to_i,
      closing_micros: row[:closing_micros]
    )
  end

  def identity(account)
    {
      id: account.id, code: account.code, name: account.name,
      direction: account.direction,
      direction_label: account.direction == Erp::VoucherLine::DEBIT ? '借' : '贷',
      category: account.category,
      category_label: Erp::LedgerAccount::CATEGORY_LABELS[account.category]
    }
  end

  # 余额落栏：正数落本方向栏，负数（异常余额）落对侧栏取绝对值。
  def split_by_direction(signed_micros, direction)
    normal_side = direction == Erp::VoucherLine::DEBIT ? :debit : :credit
    other_side = normal_side == :debit ? :credit : :debit
    return { debit: 0, credit: 0 } if signed_micros.zero?
    return { normal_side => signed_micros, other_side => 0 } if signed_micros.positive?

    { normal_side => 0, other_side => -signed_micros }
  end

  def check_of(pair, totals)
    diff = totals[pair[:debit]] - totals[pair[:credit]]
    {
      key: pair[:key], label: pair[:label],
      debit_micros: totals[pair[:debit]], credit_micros: totals[pair[:credit]],
      diff_micros: diff, balanced: diff.zero?
    }
  end

  # 全零的科目不占版面（合计是按全量末级科目算的，滤掉零行不影响数）。
  def blank_row?(row)
    TRIAL_COLUMNS.all? { |key| row[key].zero? }
  end

  def blank_balance_row?(row)
    %i[opening_micros debit_micros credit_micros ytd_debit_micros ytd_credit_micros closing_micros]
      .all? { |key| row[key].zero? }
  end

  # 本年累计：年初至 to 的借贷发生额。会计年度＝日历年（与年结服务同口径）。
  def ytd_sums(to)
    @account.erp_voucher_lines.joins(:voucher)
            .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: year_start(to)..to })
            .group(:ledger_account_id, :direction)
            .sum(:base_amount_micros)
  end

  def year_start(to)
    Date.new(to.year, 1, 1)
  end
end
