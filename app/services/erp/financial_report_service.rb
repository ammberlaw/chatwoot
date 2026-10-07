# 财务报表：资产负债表 / 利润表。基于账簿实时算（POSTED 凭证），不落中间表。
#
# 行式（行次、行名）走 Erp::ReportLines 的会企01/会企02 模板，与金蝶导出的那两张表逐字一致。
# 科目按编码前缀归入报表行；没归上的科目不会被悄悄吞掉，会单列出来（unmapped），
# 否则「资产总计」对得上、逐行却少一笔，谁都查不出来。
#
# 两个会计要点：
# 1. **备抵科目**（累计折旧/坏账准备/累计摊销，方向与大类相反）必须冲减，不能当资产加进去。
#    办法：统一折成「借方常态值」——借方科目取正、贷方科目取负，资产合计直接相加即可。
# 2. **本年利润未结转时资产负债表照样要平**：权益里加一行「本年利润（未结转）」＝损益类科目
#    当前余额净额。已结转的部分损益科目已被冲平，余额自然为 0，不会重复计。
class Erp::FinancialReportService
  # 报表段：给「科目归属段」下拉与勾稽检查用（会企01 的行式见 Erp::ReportLines）。
  BS_SECTIONS = {
    'CURRENT_ASSET' => '流动资产',
    'NON_CURRENT_ASSET' => '非流动资产',
    'CURRENT_LIABILITY' => '流动负债',
    'NON_CURRENT_LIABILITY' => '非流动负债',
    'EQUITY' => '所有者权益'
  }.freeze

  # 账套启用前的兜底起始日：资产负债表要的是「截至某日的累计余额」。
  EPOCH = Date.new(2000, 1, 1)

  def initialize(account)
    @account = account
    @query = Erp::LedgerQueryService.new(account)
  end

  # 资产负债表（时点表）：截至 as_of 的各科目累计余额。
  # 主体是会企01 的固定行式（期末余额 / 年初余额两列）；sections 是按科目列的旧视图，
  # 勾稽检查与「这一行的数从哪个科目来」还靠它，保留。
  def balance_sheet(as_of:)
    rows = leaf_rows(from: EPOCH, to: as_of)
    opening_rows = leaf_rows(from: EPOCH, to: as_of.beginning_of_year - 1)
    sections = BS_SECTIONS.keys.index_with { |section| section_lines(rows, section) }
    totals = bs_totals(sections, current_profit(rows))

    {
      as_of: as_of,
      asset_lines: bs_lines(Erp::ReportLines::BS_ASSET_LINES, rows, opening_rows, side: :asset),
      equity_lines: bs_lines(Erp::ReportLines::BS_EQUITY_LINES, rows, opening_rows, side: :equity),
      unmapped: unmapped_accounts(rows),
      sections: sections,
      totals: totals,
      balanced: totals[:assets_micros] == totals[:liabilities_and_equity_micros]
    }
  end

  # 利润表（期间表）：本期发生额口径，**排除期末结转凭证**——
  # 结转把损益科目冲平了，算进来利润表会变成 0。
  # 行式走会企02 模板；comparative=true 另算一遍上年同期（金蝶那张表的「上期金额」列）。
  def income_statement(from:, to:, comparative: true)
    current = income_values(from: from, to: to)
    prior = comparative ? income_values(from: from - 1.year, to: to - 1.year) : {}

    {
      from: from, to: to,
      rows: Erp::ReportLines::INCOME_LINES.map { |line| income_row(line, current, prior) },
      operating_profit_micros: current['operating_profit'],
      total_profit_micros: current['total_profit'],
      net_profit_micros: current['net_profit']
    }
  end

  private

  def bs_totals(sections, retained)
    assets = total_of(sections['CURRENT_ASSET']) + total_of(sections['NON_CURRENT_ASSET'])
    liabilities = total_of(sections['CURRENT_LIABILITY']) + total_of(sections['NON_CURRENT_LIABILITY'])
    equity_accounts = total_of(sections['EQUITY'])
    {
      assets_micros: assets,
      liabilities_micros: liabilities,
      equity_accounts_micros: equity_accounts,
      current_profit_micros: retained,
      equity_micros: equity_accounts + retained,
      liabilities_and_equity_micros: liabilities + equity_accounts + retained
    }
  end

  # ── 会企01/会企02 行式的取数 ──

  # 一侧（资产 / 负债和所有者权益）的报表行：取数行按前缀归集，小计行按行次相加。
  def bs_lines(template, rows, opening_rows, side:)
    current = {}
    opening = {}
    template.map do |line|
      next { heading: line[:heading] } if line[:heading]

      current[line[:no]] = bs_amount(line, rows, current, side)
      opening[line[:no]] = bs_amount(line, opening_rows, opening, side)
      bs_row(line, current, opening)
    end
  end

  def bs_row(line, current, opening)
    {
      row_no: line[:no], label: line[:label], sub: line[:sub] || false,
      total: line.key?(:sum), empty: line[:prefixes]&.empty? || false,
      amount_micros: current[line[:no]], opening_micros: opening[line[:no]]
    }
  end

  def bs_amount(line, rows, computed, side)
    if line[:sum]
      line[:sum].sum { |no| computed[no].to_i } - Array(line[:minus]).sum { |no| computed[no].to_i }
    else
      amount = prefix_amount(rows, line[:prefixes], side == :asset ? :debit : :credit)
      line[:with_current_profit] ? amount + current_profit(rows) : amount
    end
  end

  # 按编码前缀归集末级科目。sign=:debit 取借方常态值（备抵科目自然冲减），:credit 取贷方常态值。
  def prefix_amount(rows, prefixes, sign)
    return 0 if prefixes.blank?

    matched = rows.select { |row| prefixes.any? { |prefix| row[:account].code.start_with?(prefix) } }
    matched.sum { |row| sign == :credit ? credit_normal(row) : debit_normal(row) }
  end

  # 没被任何报表行收走的科目（余额不为 0 的才报）：报表总计对得上、逐行却少一笔时，
  # 问题一定出在这里，所以把它摆到报表上而不是悄悄吞掉。
  def unmapped_accounts(rows)
    prefixes = (Erp::ReportLines::BS_ASSET_LINES + Erp::ReportLines::BS_EQUITY_LINES)
               .flat_map { |line| line[:prefixes].to_a }
    rows.reject { |row| row[:account].category == 'PL' || row[:amount_micros].zero? }
        .reject { |row| prefixes.any? { |prefix| row[:account].code.start_with?(prefix) } }
        .map { |row| { id: row[:account].id, code: row[:account].code, name: row[:account].name, amount_micros: row[:amount_micros] } }
  end

  # 利润表各行金额：取数行按前缀归集，小计行按 key 相加（模板里的顺序保证被引用的行先算出来）。
  def income_values(from:, to:)
    rows = leaf_rows(from: from, to: to, period_only: true, exclude_closing: true)
    Erp::ReportLines::INCOME_LINES.each_with_object({}) do |line, values|
      next if line[:key].blank? && line[:sum].blank?

      values[line[:key]] = if line[:sum]
                             line[:sum].sum { |k| values[k].to_i } - Array(line[:minus]).sum { |k| values[k].to_i }
                           else
                             prefix_amount(rows, line[:prefixes], line[:sign])
                           end
    end
  end

  def income_row(line, current, prior)
    {
      row_no: line[:no], key: line[:key], label: line[:label],
      indent: line[:indent].to_i, sub: line[:sub] || false, total: line.key?(:sum),
      empty: line[:prefixes]&.empty? || false,
      amount_micros: current[line[:key]], prior_amount_micros: prior[line[:key]]
    }
  end

  # 只取末级科目（分类科目是汇总数，会重复计）。
  # period_only=true 时用本期发生额（利润表），否则用累计余额（资产负债表）。
  def leaf_rows(from:, to:, period_only: false, exclude_closing: false)
    balances = @query.balances(from: from, to: to, exclude_closing: exclude_closing)
    balances.reject { |row| row[:account].is_group? }.map do |row|
      amount = if period_only
                 directional(row[:account].direction, row[:debit_micros], row[:credit_micros])
               else
                 row[:closing_micros]
               end
      { account: row[:account], amount_micros: amount }
    end
  end

  def directional(direction, debit, credit)
    direction == Erp::VoucherLine::DEBIT ? debit - credit : credit - debit
  end

  # 借方常态值：借方科目取正、贷方科目取负。备抵科目（累计折旧等）因此自动冲减。
  def debit_normal(row)
    row[:account].direction == Erp::VoucherLine::DEBIT ? row[:amount_micros] : -row[:amount_micros]
  end

  def credit_normal(row)
    -debit_normal(row)
  end

  def section_lines(rows, section)
    liability_side = section.include?('LIABILITY') || section == 'EQUITY'
    rows.select { |row| row[:account].bs_section == section }
        .map { |row| line_of(row, liability_side) }
        .reject { |line| line[:amount_micros].zero? }
  end

  def line_of(row, liability_side)
    {
      # id 给前端钻明细账用（财务要的「取数」：这一行的数从哪个科目来）。
      id: row[:account].id,
      code: row[:account].code,
      name: row[:account].name,
      amount_micros: liability_side ? credit_normal(row) : debit_normal(row)
    }
  end

  def total_of(lines)
    lines.sum { |line| line[:amount_micros] }
  end

  # 本年利润（未结转）：损益类科目余额净额，收入为正、费用为负。
  def current_profit(rows)
    rows.select { |row| row[:account].category == 'PL' }.sum { |row| credit_normal(row) }
  end
end
