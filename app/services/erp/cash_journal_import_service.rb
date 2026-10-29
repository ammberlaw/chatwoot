# 银行日记账 Excel 导入（财务 2026-10-29 需求③）。
#
# 认金蝶「出纳-日记账」导出的那套列头：
#   账户.名称 / 币别.名称 / 日期 / 业务日期 / 日记账编号 / 摘要 / 收入金额 / 支出金额 / 汇率
# 各家叫法不一，常见几种都认（同物料单价导入的做法）。
#
# 口径：
#   1. **账户按名称匹配资金账户**（erp_cash_accounts.name）。对不上的整行退回并列出来，
#      不自动建账户——银行账户是主数据，建错了对不上账比少导几行严重得多。
#   2. 收入金额 → IN，支出金额 → OUT。两列都有数或都没数的行退回（方向判不出来）。
#   3. **按「账户＋日期＋编号」判重**，重复导入同一个文件不会翻倍。日记账编号为空时
#      退化成「账户＋日期＋摘要＋金额」——财务手工整理的表常常不带编号。
#   4. 只落日记账流水，**不生成凭证**。生成凭证是需求④，财务要自己挑模板和期间。
class Erp::CashJournalImportService
  class Error < StandardError; end

  require 'roo'

  HEADER_SCAN_ROWS = 6
  ACCOUNT_HEADERS = ['账户.名称', '账户', '银行账户', 'account.name'].freeze
  DATE_HEADERS = %w[日期 记账日期 date].freeze
  BIZ_DATE_HEADERS = %w[业务日期 bizdate].freeze
  NO_HEADERS = %w[日记账编号 编号 number].freeze
  SUMMARY_HEADERS = %w[摘要 事由 explanation].freeze
  DEBIT_HEADERS = %w[收入金额 收入 借方金额 debitfor].freeze
  CREDIT_HEADERS = %w[支出金额 支出 贷方金额 creditfor].freeze
  CURRENCY_HEADERS = ['币别.名称', '币别', '币种', 'currency.name'].freeze
  RATE_HEADERS = %w[汇率 exchangerate].freeze
  COUNTERPARTY_HEADERS = %w[往来单位 对方单位 结算客户 结算供应商].freeze

  # 表里写的是中文币种名，库里存的是代码。
  CURRENCY_CODES = { '人民币' => 'CNY', '美元' => 'USD', '港币' => 'HKD',
                     '欧元' => 'EUR', '日元' => 'JPY', '英镑' => 'GBP' }.freeze

  def initialize(account:, user:, path:)
    @account = account
    @user = user
    @path = path
  end

  def import!
    rows = parse
    raise Error, '文件里没有数据行' if rows.empty?

    @missing_accounts = []
    @bad_rows = []
    @created = 0
    @skipped = 0
    accounts = cash_accounts_by_name
    ActiveRecord::Base.transaction { rows.each { |row| apply_row(row, accounts) } }

    { rows: rows.size, created: @created, skipped: @skipped,
      missing_account_count: @missing_accounts.size,
      missing_accounts: @missing_accounts.uniq.first(20),
      bad_row_count: @bad_rows.size, bad_rows: @bad_rows.first(20) }
  end

  private

  # 账户名去掉空格再比：财务表里常写成「陈总民生银行 4443尾号」，库里是「陈总民生银行4443尾号」。
  def cash_accounts_by_name
    @account.erp_cash_accounts.index_by do |a|
      normalize(a.name)
    end
  end

  def normalize(value) = value.to_s.gsub(/[[:space:]]/, '').downcase

  def apply_row(row, accounts)
    cash_account = accounts[normalize(row[:account_name])]
    return @missing_accounts << row[:account_name] if cash_account.nil?
    return @bad_rows << "第 #{row[:line]} 行：收入与支出只能填一个" if row[:direction].nil?
    return @skipped += 1 if duplicate?(row, cash_account)

    @account.erp_cash_transactions.create!(
      cash_account: cash_account, direction: row[:direction],
      amount_micros: row[:amount], currency: row[:currency],
      exchange_rate: row[:rate], happened_at: row[:date],
      summary: row[:summary], counterparty: row[:counterparty],
      created_by: @user
    )
    @created += 1
  end

  # 同一个账户、同一天、同一笔号就是同一条。没编号时拿摘要+金额当指纹。
  def duplicate?(row, cash_account)
    scope = @account.erp_cash_transactions
                    .where(cash_account_id: cash_account.id, happened_at: row[:date])
    scope = if row[:no].present?
              scope.where(summary: row[:summary]).where(amount_micros: row[:amount])
            else
              scope.where(summary: row[:summary], amount_micros: row[:amount],
                          direction: row[:direction])
            end
    scope.exists?
  end

  def parse
    sheet = open_sheet
    header_row, cols = find_header(sheet)
    raise Error, "表头里找不到「#{ACCOUNT_HEADERS.first}」列" if header_row.nil?
    raise Error, "表头里找不到「#{DATE_HEADERS.first}」列" if cols[:date].nil?

    ((header_row + 1)..sheet.last_row).filter_map { |i| row_at(sheet, cols, i) }
  end

  def row_at(sheet, cols, index)
    name = cell(sheet, index, cols[:account])
    date = to_date(sheet.cell(index, cols[:date]))
    return nil if name.blank? || date.nil?

    debit = to_micros(cell(sheet, index, cols[:debit]))
    credit = to_micros(cell(sheet, index, cols[:credit]))
    { line: index, account_name: name, date: date,
      direction: direction_of(debit, credit),
      amount: debit.positive? ? debit : credit }.merge(text_fields(sheet, cols, index))
  end

  def text_fields(sheet, cols, index)
    { no: cell(sheet, index, cols[:no]),
      summary: cell(sheet, index, cols[:summary]),
      counterparty: cell(sheet, index, cols[:counterparty]).presence,
      currency: CURRENCY_CODES[cell(sheet, index, cols[:currency])] || 'CNY',
      rate: to_rate(cell(sheet, index, cols[:rate])) }
  end

  # 收入和支出只能有一个有数；都有或都没有就判不出方向。
  def direction_of(debit, credit)
    return Erp::CashTransaction::IN if debit.positive? && credit.zero?
    return Erp::CashTransaction::OUT if credit.positive? && debit.zero?

    nil
  end

  def cell(sheet, row, col)
    col && sheet.cell(row, col).to_s.strip
  end

  def open_sheet
    Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
  rescue StandardError => e
    raise Error, "读取 Excel 失败：#{e.message}"
  end

  # 表头不一定在第一行：金蝶模板第 1~2 行是表名和填写说明。
  def find_header(sheet)
    (1..[HEADER_SCAN_ROWS, sheet.last_row].min).each do |i|
      cells = (1..sheet.last_column).map { |c| sheet.cell(i, c).to_s.strip }
      account_col = col_of(cells, ACCOUNT_HEADERS)
      next if account_col.nil?

      return [i, header_cols(cells, account_col)]
    end
    [nil, {}]
  end

  def header_cols(cells, account_col)
    { account: account_col, date: col_of(cells, DATE_HEADERS),
      biz_date: col_of(cells, BIZ_DATE_HEADERS), no: col_of(cells, NO_HEADERS),
      summary: col_of(cells, SUMMARY_HEADERS), debit: col_of(cells, DEBIT_HEADERS),
      credit: col_of(cells, CREDIT_HEADERS), currency: col_of(cells, CURRENCY_HEADERS),
      rate: col_of(cells, RATE_HEADERS), counterparty: col_of(cells, COUNTERPARTY_HEADERS) }
  end

  # 列头常带 *、# 和英文字段名（「*账户.名称 # account.name」），取能匹配上的那个。
  def col_of(cells, names)
    idx = cells.index { |c| names.any? { |n| normalize(c).include?(normalize(n)) } }
    idx && (idx + 1)
  end

  def to_date(value)
    return value.to_date if value.respond_to?(:to_date) && !value.is_a?(String)

    text = value.to_s.strip
    return nil if text.blank?

    Date.parse(text.tr('/.', '--'))
  rescue ArgumentError, RangeError
    nil
  end

  def to_micros(value)
    return 0 if value.blank?

    (value.to_s.gsub(/[^\d.\-]/, '').to_d * 1_000_000).round
  rescue ArgumentError
    0
  end

  def to_rate(value)
    rate = value.to_s.gsub(/[^\d.]/, '').to_d
    rate.positive? ? rate : 1
  rescue ArgumentError
    1
  end
end
