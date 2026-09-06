# 财务报表：资产负债表 / 利润表。基于账簿实时算（POSTED 凭证），不落中间表。
#
# 两个会计要点：
# 1. **备抵科目**（累计折旧/坏账准备/累计摊销，方向与大类相反）必须冲减，不能当资产加进去。
#    办法：统一折成「借方常态值」——借方科目取正、贷方科目取负，资产合计直接相加即可。
# 2. **本年利润未结转时资产负债表照样要平**：权益里加一行「本年利润（未结转）」＝损益类科目
#    当前余额净额。已结转的部分损益科目已被冲平，余额自然为 0，不会重复计。
class Erp::FinancialReportService
  # 利润表行式（中国准则常用口径）：科目编码前缀 → 报表行，子科目自动归入父行。
  INCOME_ROWS = [
    { key: 'revenue', label: '一、营业收入', prefixes: %w[6001 6021], sign: :credit },
    { key: 'cost', label: '减：营业成本', prefixes: %w[6401 6402], sign: :debit },
    { key: 'tax_surcharge', label: '　　税金及附加', prefixes: %w[6403], sign: :debit },
    { key: 'selling', label: '　　销售费用', prefixes: %w[6601], sign: :debit },
    { key: 'admin', label: '　　管理费用', prefixes: %w[6602], sign: :debit },
    { key: 'finance', label: '　　财务费用', prefixes: %w[6603], sign: :debit },
    { key: 'impairment', label: '　　资产减值损失', prefixes: %w[6701 6702], sign: :debit },
    { key: 'other_income', label: '加：其他收益', prefixes: %w[6051], sign: :credit },
    { key: 'investment', label: '　　投资收益', prefixes: %w[6111], sign: :credit },
    { key: 'interest_income', label: '　　利息收入', prefixes: %w[6011], sign: :credit },
    { key: 'asset_disposal', label: '　　资产处置损益', prefixes: %w[6115], sign: :credit },
    { key: 'non_operating_income', label: '加：营业外收入', prefixes: %w[6301], sign: :credit },
    { key: 'non_operating_expense', label: '减：营业外支出', prefixes: %w[6711], sign: :debit },
    { key: 'income_tax', label: '减：所得税费用', prefixes: %w[6801], sign: :debit }
  ].freeze

  # 营业利润 = 收入 - 成本费用 + 其他经营性收益
  OPERATING_PLUS = %w[revenue other_income investment interest_income asset_disposal].freeze
  OPERATING_MINUS = %w[cost tax_surcharge selling admin finance impairment].freeze

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

  # 资产负债表（时点表）：截至 as_of 的各科目累计余额，按报表段分组。
  def balance_sheet(as_of:)
    rows = leaf_rows(from: EPOCH, to: as_of)
    sections = BS_SECTIONS.keys.index_with { |section| section_lines(rows, section) }

    assets = total_of(sections['CURRENT_ASSET']) + total_of(sections['NON_CURRENT_ASSET'])
    liabilities = total_of(sections['CURRENT_LIABILITY']) + total_of(sections['NON_CURRENT_LIABILITY'])
    equity_accounts = total_of(sections['EQUITY'])
    retained = current_profit(rows)

    {
      as_of: as_of,
      sections: sections,
      totals: {
        assets_micros: assets,
        liabilities_micros: liabilities,
        equity_accounts_micros: equity_accounts,
        current_profit_micros: retained,
        equity_micros: equity_accounts + retained,
        liabilities_and_equity_micros: liabilities + equity_accounts + retained
      },
      balanced: assets == liabilities + equity_accounts + retained
    }
  end

  # 利润表（期间表）：本期发生额口径，**排除期末结转凭证**——
  # 结转把损益科目冲平了，算进来利润表会变成 0。
  def income_statement(from:, to:)
    rows = leaf_rows(from: from, to: to, period_only: true, exclude_closing: true)
    values = INCOME_ROWS.index_with { |row| row_amount(rows, row) }

    operating = OPERATING_PLUS.sum { |k| values[find_row(k)] } - OPERATING_MINUS.sum { |k| values[find_row(k)] }
    total_profit = operating + values[find_row('non_operating_income')] - values[find_row('non_operating_expense')]
    net_profit = total_profit - values[find_row('income_tax')]

    {
      from: from, to: to,
      rows: INCOME_ROWS.map { |row| { key: row[:key], label: row[:label], amount_micros: values[row] } },
      operating_profit_micros: operating,
      total_profit_micros: total_profit,
      net_profit_micros: net_profit
    }
  end

  private

  def find_row(key)
    INCOME_ROWS.find { |row| row[:key] == key }
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

  def row_amount(rows, spec)
    matched = rows.select { |row| spec[:prefixes].any? { |prefix| row[:account].code.start_with?(prefix) } }
    matched.sum { |row| spec[:sign] == :credit ? credit_normal(row) : debit_normal(row) }
  end
end
