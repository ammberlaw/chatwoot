# 勾稽检查（财务要的「资产负债表与各科目余额的勾稽关系」）：
# 不只报一个差额，而是把**会让报表悄悄不平的原因**逐条点名。
#
# 最容易出事的是第 ③ 条：末级科目没设「资产负债表归属段」且不是损益类，
# 它的余额既进不了资产负债表任何一段、也不算进本年利润，于是**凭空消失**——
# 两边差出来还看不出是谁。国标科目表里 5001 生产成本 / 5101 制造费用 / 5201 劳务成本
# 出厂就是这个状态（成本类、无归属段），它们一有余额（在产品）就会砸出这个坑。
#
# 本服务只做核对，不改数：口径全部复用资产负债表/利润表/账簿，
# 免得「检查」自己算一套、跟报表对不上。
class Erp::TieCheckService
  def initialize(account)
    @account = account
    @query = Erp::LedgerQueryService.new(account)
    @report = Erp::FinancialReportService.new(account)
  end

  def run(as_of:)
    sheet = @report.balance_sheet(as_of: as_of)
    rows = leaf_rows(from: Erp::FinancialReportService::EPOCH, to: as_of)

    {
      as_of: as_of,
      checks: [
        trial_balance_check(as_of),
        sheet_balance_check(sheet),
        unmapped_accounts_check(rows),
        double_counted_check(rows),
        profit_tie_check(as_of, sheet)
      ]
    }
  end

  private

  # ① 账本身平不平：截至 as_of 的全部已记账分录，借方合计＝贷方合计。
  # 这是资产负债表能平的地基——地基塌了，上面每张报表都不用看。
  def trial_balance_check(as_of)
    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: ..as_of })
                   .group(:direction).sum(:base_amount_micros)
    debit = sums[Erp::VoucherLine::DEBIT].to_i
    credit = sums[Erp::VoucherLine::CREDIT].to_i

    check('trial', '全部已记账凭证借贷平衡', debit == credit,
          detail: { debit_micros: debit, credit_micros: credit, diff_micros: debit - credit },
          hint: '不平说明有凭证绕过了平衡校验落库，须逐张排查，后面几条先别看')
  end

  # ② 资产 = 负债 + 所有者权益（含未结转本年利润）。
  def sheet_balance_check(sheet)
    totals = sheet[:totals]
    diff = totals[:assets_micros] - totals[:liabilities_and_equity_micros]

    check('sheet', '资产合计 = 负债和所有者权益合计', diff.zero?,
          detail: { assets_micros: totals[:assets_micros],
                    liabilities_and_equity_micros: totals[:liabilities_and_equity_micros],
                    diff_micros: diff },
          hint: '有差额时看下面第 ③ ④ 条，差额几乎总是科目的归属段设错造成的')
  end

  # ③ 有余额却掉出报表的科目：非损益类 + 没设归属段。
  def unmapped_accounts_check(rows)
    orphans = rows.select do |row|
      row[:closing_micros] != 0 && row[:account].category != 'PL' && row[:account].bs_section.blank?
    end

    check('unmapped', '所有有余额的科目都进了报表', orphans.empty?,
          detail: { accounts: orphans.map { |row| account_line(row, row[:closing_micros]) } },
          hint: '到「科目表」给这些科目设「资产负债表归属段」——在产品性质的成本类科目归流动资产（存货）')
  end

  # ④ 损益类科目被设了归属段：会被计两遍（既进报表段，又进本年利润）。
  def double_counted_check(rows)
    dupes = rows.select { |row| row[:account].category == 'PL' && row[:account].bs_section.present? }

    check('double_counted', '损益类科目未被重复计入', dupes.empty?,
          detail: { accounts: dupes.map { |row| account_line(row, row[:closing_micros]) } },
          hint: '损益类科目不该有「资产负债表归属段」，它们通过「本年利润」进表，设了就是算两遍')
  end

  # ⑤ 表间勾稽：资产负债表的本年利润 = 利润表本年累计净利润。
  # 未结转部分挂在损益科目上（就是资产负债表那行「本年利润（未结转）」），
  # 已结转部分走了本年利润科目，故左边要把本年利润科目的**本年发生净额**加回来
  # （取发生额而非余额：跨年没做年结也不会因为上年余额残留而误报）。
  def profit_tie_check(as_of, sheet)
    unclosed = sheet[:totals][:current_profit_micros]
    closed = year_profit_movement(as_of)
    net_profit = @report.income_statement(from: year_start(as_of), to: as_of)[:net_profit_micros]
    diff = unclosed + closed - net_profit

    check('profit', '本年利润与利润表净利润勾稽', diff.zero?,
          detail: { unclosed_micros: unclosed, closed_micros: closed,
                    net_profit_micros: net_profit, diff_micros: diff,
                    uncovered_accounts: uncovered_pl_accounts(as_of) },
          hint: '两种原因：下面列出的损益科目编码不在利润表行次里所以取不到数；' \
                '或跨年没做年结，上年损益还挂在损益科目上')
  end

  # 本年利润科目（4103）本年发生净额：贷 − 借。
  def year_profit_movement(as_of)
    ids = @account.erp_ledger_accounts.where(account_type: 'YEAR_PROFIT').ids
    return 0 if ids.empty?

    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(ledger_account_id: ids)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED,
                                          voucher_date: year_start(as_of)..as_of })
                   .group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::CREDIT].to_i - sums[Erp::VoucherLine::DEBIT].to_i
  end

  # 利润表按科目编码前缀取数，前缀没覆盖到的损益科目会被漏掉——把有发生额的那些点出来。
  def uncovered_pl_accounts(as_of)
    prefixes = Erp::FinancialReportService::INCOME_ROWS.flat_map { |row| row[:prefixes] }
    rows = leaf_rows(from: year_start(as_of), to: as_of, exclude_closing: true)
    missed = rows.select do |row|
      row[:account].category == 'PL' && (row[:debit_micros] + row[:credit_micros]) != 0 &&
        prefixes.none? { |prefix| row[:account].code.start_with?(prefix) }
    end
    missed.map { |row| account_line(row, row[:debit_micros] + row[:credit_micros]) }
  end

  def leaf_rows(from:, to:, exclude_closing: false)
    @query.balances(from: from, to: to, exclude_closing: exclude_closing)
          .reject { |row| row[:account].is_group? }
  end

  def account_line(row, amount_micros)
    account = row[:account]
    { id: account.id, code: account.code, name: account.name,
      category_label: Erp::LedgerAccount::CATEGORY_LABELS[account.category],
      amount_micros: amount_micros }
  end

  def check(key, label, passed, detail:, hint:)
    { key: key, label: label, passed: passed, detail: detail, hint: passed ? nil : hint }
  end

  def year_start(as_of)
    Date.new(as_of.year, 1, 1)
  end
end
