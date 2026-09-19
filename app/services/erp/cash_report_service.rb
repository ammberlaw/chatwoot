# 资金报表（ERP_SPEC §9.3）：各账户的期初 / 本期收 / 本期支 / 期末 + 折 CNY 合计。
#
# 资金页只显示「当前余额」，财务要的是**一个期间里钱怎么进出的**——月末对账、
# 给老板看现金流，都得有这张表。
#
# 口径（三条，错一条对不上账）：
# 1. **原币是主口径**：每个账户按自己的币种出四个数，这列要能跟银行对账单逐笔对上。
#    期末 = 期初 + 收 − 支，恒等式必须成立（日记账只增不改，见 §13-7）。
# 2. **折 CNY 走账面本位币**（各笔流水按发生日汇率折算的累计），不是按期末汇率重估。
#    理由是这张表要和总账上的资金科目对得上；期末汇率重估是调汇（RevaluationService）
#    干的活，两件事混在一起，两账对平那页就会天天飘。
# 3. **外币账户没填期初本位币就不猜**：opening_base_amount_micros 为 NULL 时该账户
#    本位币列返回 nil、并从合计里剔除，页面显式提示缺哪几个账户。
#    按 1:1 加进去正是看板刚修掉的那个错（USD 当 CNY 加）。
class Erp::CashReportService
  BASE_CURRENCY = 'CNY'.freeze

  def initialize(account)
    @account = account
  end

  # period 形如 '2026-09'；返回 { period:, from:, to:, rows:, totals:, missing_base_accounts: }
  def call(period:)
    from = Date.strptime(period, '%Y-%m').beginning_of_month
    to = from.end_of_month
    rows = accounts.map { |cash_account| row_for(cash_account, from, to) }
    { period: period, from: from, to: to, rows: rows,
      totals: totals_of(rows), by_currency: by_currency(rows),
      missing_base_accounts: rows.select { |row| row[:base_unknown] }.pluck(:name) }
  rescue ArgumentError
    raise ArgumentError, '期间格式应为 YYYY-MM'
  end

  private

  def accounts
    @account.erp_cash_accounts.order(:position, :id).to_a
  end

  def row_for(cash_account, from, to)
    opening = opening_of(cash_account, from)
    period_in = sum_of(cash_account, from..to, Erp::CashTransaction::IN)
    period_out = sum_of(cash_account, from..to, Erp::CashTransaction::OUT)
    base = base_figures(cash_account, opening, period_in, period_out)

    {
      id: cash_account.id, name: cash_account.name,
      kind_label: Erp::CashAccount::KIND_LABELS[cash_account.kind],
      currency: cash_account.currency, is_active: cash_account.is_active,
      opening_micros: opening[:amount], in_micros: period_in[:amount], out_micros: period_out[:amount],
      closing_micros: opening[:amount] + period_in[:amount] - period_out[:amount]
    }.merge(base)
  end

  # 期初 = 账户期初余额 + 期间开始日之前的流水净额（原币与本位币各算一份）。
  def opening_of(cash_account, from)
    before = cash_account.transactions.where(happened_at: ...from)
    net = before.sum { |row| signed(row, :amount_micros) }
    base_net = before.sum { |row| signed(row, :base_amount_micros) }
    {
      amount: cash_account.opening_balance_micros + net,
      base: opening_base(cash_account)&.+(base_net)
    }
  end

  # 本位币期初基准：CNY 账户就是原币；外币账户要财务填过才有，没填返回 nil。
  def opening_base(cash_account)
    return cash_account.opening_balance_micros if cash_account.currency == BASE_CURRENCY

    cash_account.opening_base_amount_micros
  end

  def sum_of(cash_account, range, direction)
    rows = cash_account.transactions.where(happened_at: range, direction: direction)
    { amount: rows.sum(:amount_micros), base: rows.sum(&:base_amount_micros) }
  end

  def signed(row, field)
    value = row.public_send(field)
    row.direction == Erp::CashTransaction::IN ? value : -value
  end

  # 期初本位币未知时，期末本位币也就无从谈起——整行本位币置 nil，别用发生额充数。
  def base_figures(cash_account, opening, period_in, period_out)
    return base_unknown_row(period_in, period_out) if opening[:base].nil?

    {
      base_unknown: false, is_base_currency: cash_account.currency == BASE_CURRENCY,
      opening_base_micros: opening[:base],
      in_base_micros: period_in[:base], out_base_micros: period_out[:base],
      closing_base_micros: opening[:base] + period_in[:base] - period_out[:base]
    }
  end

  def base_unknown_row(period_in, period_out)
    {
      base_unknown: true, is_base_currency: false,
      opening_base_micros: nil, closing_base_micros: nil,
      in_base_micros: period_in[:base], out_base_micros: period_out[:base]
    }
  end

  # 合计只加本位币可算的账户；缺期初本位币的外币账户不计入（页面另行提示）。
  def totals_of(rows)
    countable = rows.reject { |row| row[:base_unknown] }
    %i[opening_base_micros in_base_micros out_base_micros closing_base_micros].index_with do |key|
      countable.sum { |row| row[key].to_i }
    end
  end

  # 按币种小计原币，外币账户不折算也能看出各币种的进出。
  CURRENCY_SUBTOTAL_KEYS = %i[opening_micros in_micros out_micros closing_micros].freeze

  def by_currency(rows)
    groups = rows.group_by { |row| row[:currency] }.map { |currency, items| currency_subtotal(currency, items) }
    groups.sort_by { |row| row[:currency] == BASE_CURRENCY ? '' : row[:currency] }
  end

  def currency_subtotal(currency, items)
    sums = CURRENCY_SUBTOTAL_KEYS.index_with { |key| items.sum { |row| row[key] } }
    sums.merge(currency: currency)
  end
end
