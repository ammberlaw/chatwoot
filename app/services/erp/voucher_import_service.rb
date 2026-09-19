# 凭证批量导入（CSV）。用于账套启用时把历史凭证一次性搬进来，也用于从别的系统导。
#
# 表头（第一行，中文，顺序不限）：
#   组号 | 日期 | 事由 | 摘要 | 科目编码 | 借方金额 | 贷方金额 | 币种 | 汇率 | 客户 | 供应商
# **组号相同的行合成一张凭证**（一借多贷就写同一个组号多行）。
#
# 两条硬规则：
# 1. **整组要么全进、要么全不进**：一张凭证里有一行错，这张就整张不建，错误逐行报出来；
#    其它凭证照常建。半张凭证进账比不进账更难收拾。
# 2. 生成的一律是**待过账**凭证，导进来还要财务逐张审过账——导入不等于记账。
class Erp::VoucherImportService
  class Error < StandardError; end

  HEADERS = {
    '组号' => :group, '日期' => :date, '事由' => :voucher_summary, '摘要' => :summary,
    '科目编码' => :code, '借方金额' => :debit, '贷方金额' => :credit,
    '币种' => :currency, '汇率' => :rate, '客户' => :customer, '供应商' => :supplier
  }.freeze

  REQUIRED_HEADERS = %w[组号 日期 科目编码].freeze

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 返回 { created: [凭证号...], failed: [{ group:, errors: [...] }], total_groups: }
  def import!(csv_text)
    rows = parse(csv_text)
    raise Error, 'CSV 里没有数据行' if rows.empty?

    groups = rows.group_by { |row| row[:group].to_s.strip }
    result = { created: [], failed: [], total_groups: groups.size }
    groups.each { |group, group_rows| build_group(group, group_rows, result) }
    result
  end

  # 导入模板 CSV（给页面「下载模板」用）。
  def self.template_csv
    CSV.generate(encoding: 'UTF-8') do |csv|
      csv << HEADERS.keys
      csv << ['1', '2026-08-31', '支付8月房租', '房租', '660203', '5000', '', 'CNY', '1', '', '']
      csv << ['1', '2026-08-31', '支付8月房租', '房租', '100201', '', '5000', 'CNY', '1', '', '']
    end
  end

  private

  def parse(csv_text)
    table = CSV.parse(csv_text.to_s.delete_prefix("\xEF\xBB\xBF"), headers: true)
    missing = REQUIRED_HEADERS - table.headers.compact.map(&:strip)
    raise Error, "CSV 缺少必需的列：#{missing.join('、')}" if missing.any?

    table.map { |row| normalize_row(row) }.reject { |row| row[:code].blank? }
  end

  def normalize_row(row)
    HEADERS.to_h { |header, key| [key, row[header]&.strip] }
  end

  def build_group(group, group_rows, result)
    lines = group_rows.each_with_index.map { |row, index| build_line(row, index) }
    voucher = create_voucher!(group_rows.first, lines)
    result[:created] << voucher.voucher_no
  rescue Error, ActiveRecord::RecordInvalid => e
    result[:failed] << { group: group, errors: [e.message] }
  end

  def create_voucher!(first_row, lines)
    voucher = @account.erp_vouchers.create!(
      voucher_date: parse_date(first_row[:date]), status: Erp::Voucher::DRAFT,
      summary: first_row[:voucher_summary].presence, prepared_by_id: @user&.id,
      source_type: 'Erp::Import', lines_attributes: lines
    )
    voucher.refresh_totals!
    voucher
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue Date::Error
    raise Error, "日期「#{value}」看不懂，请用 2026-08-31 这种写法"
  end

  def build_line(row, position)
    ledger_account = find_account!(row[:code])
    debit = to_micros(row[:debit])
    credit = to_micros(row[:credit])
    raise Error, "科目 #{row[:code]} 这行的借方和贷方只能填一个，且必须大于 0" unless debit.positive? ^ credit.positive?

    {
      ledger_account_id: ledger_account.id, position: position,
      direction: debit.positive? ? Erp::VoucherLine::DEBIT : Erp::VoucherLine::CREDIT,
      amount_micros: debit.positive? ? debit : credit,
      summary: row[:summary].presence, currency: row[:currency].presence || 'CNY',
      exchange_rate: row[:rate].presence || 1
    }.merge(dimensions_for(row, ledger_account))
  end

  def find_account!(code)
    ledger_account = @account.erp_ledger_accounts.active.leaves.find_by(code: code)
    raise Error, "找不到启用中的末级科目「#{code}」" if ledger_account.blank?

    ledger_account
  end

  # 往来科目按名称精确匹配客户/供应商——匹配不上直接报错，不静默留空
  # （应收不挂客户，往来对账就查不出谁欠钱）。
  def dimensions_for(row, ledger_account)
    case ledger_account.required_dimension
    when 'customer' then { crm_customer_id: find_party!(@account.crm_customers, row[:customer], '客户', ledger_account) }
    when 'supplier' then { mes_supplier_id: find_party!(@account.mes_suppliers, row[:supplier], '供应商', ledger_account) }
    else {}
    end
  end

  def find_party!(scope, name, label, ledger_account)
    raise Error, "科目「#{ledger_account.label}」是往来科目，必须填#{label}" if name.blank?

    matches = scope.where(name: name).limit(2).to_a
    raise Error, "#{label}「#{name}」在系统里找不到（要跟系统里的名称完全一致）" if matches.empty?
    # 迁移数据里同名客户真实存在：静默取第一条会把应收挂到别人头上，对账/催款全找错人。
    raise Error, "#{label}「#{name}」在系统里有多条同名记录，无法确定挂哪一条；请先在查重板块合并或改名后再导入" if matches.size > 1

    matches.first.id
  end

  def to_micros(value)
    return 0 if value.blank?

    (value.to_s.delete(',').to_d * 1_000_000).round
  end
end
