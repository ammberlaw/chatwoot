# 审计接口 / 标准财务数据导出：把一个期间区间的账套数据打成一个 zip，交给会计师事务所。
#
# 包内容：
#   01_科目表.csv       科目编码/名称/类别/余额方向/是否明细
#   02_凭证序时簿.csv    逐笔分录（凭证号·日期·摘要·科目·借贷·原币·维度·制单记账人）
#   03_科目余额表.csv    期初 / 本期借贷发生 / 期末
#   04_会计数据.xml     国标《会计核算软件数据接口》结构的 XML
#   导出说明.txt        口径说明
#
# 口径：**只导已记账（POSTED）凭证**——草稿和作废凭证不是账，不该出现在给审计的数据里。
#
# ⚠️ XML 那份是按国标结构生成的，但各家事务所的导入工具对字段/版本要求不一。
#    第一次年审前务必先让事务所拿一份小样试导，别等交表当天才发现要调。
#    CSV 三件套是通用兜底，事务所基本都收。
class Erp::AuditExportService
  BOM = "\xEF\xBB\xBF".freeze

  def initialize(account)
    @account = account
    @query = Erp::LedgerQueryService.new(account)
  end

  # 返回 zip 的二进制内容。
  def export(from:, to:)
    files = {
      '01_科目表.csv' => accounts_csv,
      '02_凭证序时簿.csv' => journal_csv(from, to),
      '03_科目余额表.csv' => balances_csv(from, to),
      '04_会计数据.xml' => xml(from, to),
      '导出说明.txt' => readme(from, to)
    }
    zip(files)
  end

  def filename(from:, to:)
    "#{@account.name}_财务数据_#{from}_至_#{to}.zip"
  end

  # 金额与人名的统一写法；Erp::AuditXmlBuilder 也用这两个，故为公开方法。
  def yuan(micros)
    return nil if micros.nil?

    format('%.2f', micros / 1_000_000.0)
  end

  def person(user)
    user&.name.presence || user&.crm_name
  end

  private

  # 文件名是中文，必须置 general purpose flag 的 bit 11（UTF-8 文件名标志），
  # 否则 Windows 自带解压出来是乱码——事务所基本都在 Windows 上开。
  UTF8_NAME_FLAG = 0x0800

  def zip(files)
    buffer = Zip::OutputStream.write_buffer do |out|
      files.each do |name, content|
        entry = Zip::Entry.new('', name)
        entry.gp_flags |= UTF8_NAME_FLAG
        out.put_next_entry(entry)
        out.write(content)
      end
    end
    buffer.string
  end

  def ledger_accounts
    # 科目表要输出「上级编码」，不预加载 parent 就是一个科目一次查询（109 个科目 109 次）。
    @ledger_accounts ||= @account.erp_ledger_accounts.includes(:parent).order(:code).to_a
  end

  # 只认已记账凭证：草稿与作废不是账。
  def posted_lines(from, to)
    @account.erp_voucher_lines
            .joins(:voucher)
            .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: from..to })
            .includes(:ledger_account, :crm_customer, :mes_supplier, :crm_sales_order,
                      voucher: [:prepared_by, :posted_by])
            .order('erp_vouchers.voucher_date ASC, erp_vouchers.voucher_no ASC, erp_voucher_lines.position ASC')
  end

  def accounts_csv
    csv_with_bom(%w[科目编码 科目名称 上级编码 科目类别 余额方向 是否明细科目 是否启用 币种]) do |csv|
      ledger_accounts.each do |item|
        csv << [
          item.code, item.name, item.parent&.code,
          Erp::LedgerAccount::CATEGORY_LABELS[item.category],
          item.direction == Erp::VoucherLine::DEBIT ? '借' : '贷',
          item.is_group? ? '否' : '是', item.is_active? ? '是' : '否', item.currency
        ]
      end
    end
  end

  JOURNAL_HEADERS = %w[
    凭证号 凭证日期 会计期间 凭证事由 分录摘要 科目编码 科目名称
    借方金额 贷方金额 币种 汇率 原币金额 客户 供应商 订单号 制单人 记账人
  ].freeze

  def journal_csv(from, to)
    csv_with_bom(JOURNAL_HEADERS) do |csv|
      posted_lines(from, to).each { |line| csv << journal_row(line) }
    end
  end

  def journal_row(line)
    voucher = line.voucher
    [voucher.voucher_no, voucher.voucher_date, voucher.period, voucher.summary, line.summary,
     line.ledger_account.code, line.ledger_account.name] +
      amount_columns(line) +
      [line.crm_customer&.name, line.mes_supplier&.name, line.crm_sales_order&.order_no,
       person(voucher.prepared_by), person(voucher.posted_by)]
  end

  # 借方 / 贷方 / 币种 / 汇率 / 原币金额
  def amount_columns(line)
    base = yuan(line.base_amount_micros)
    debit = line.direction == Erp::VoucherLine::DEBIT
    [debit ? base : nil, debit ? nil : base, line.currency, line.exchange_rate, yuan(line.amount_micros)]
  end

  def balances_csv(from, to)
    rows = @query.balances(from: from, to: to)
    headers = %w[科目编码 科目名称 是否明细科目 期初余额 本期借方发生 本期贷方发生 期末余额 余额方向]
    csv_with_bom(headers) do |csv|
      rows.each do |row|
        item = row[:account]
        csv << [
          item.code, item.name, item.is_group? ? '否' : '是',
          yuan(row[:opening_micros]), yuan(row[:debit_micros]), yuan(row[:credit_micros]),
          yuan(row[:closing_micros]), item.direction == Erp::VoucherLine::DEBIT ? '借' : '贷'
        ]
      end
    end
  end

  def csv_with_bom(headers)
    BOM + CSV.generate(encoding: 'UTF-8') do |csv|
      csv << headers
      yield Erp::SanitizingCsv.new(csv)
    end
  end

  def xml(from, to)
    Erp::AuditXmlBuilder.new(@account, self)
                        .build(from: from, to: to, ledger_accounts: ledger_accounts, lines: posted_lines(from, to))
  end

  def readme(from, to)
    <<~TEXT
      #{@account.name} 财务数据导出
      期间：#{from} 至 #{to}
      导出时间：#{Time.current.strftime('%Y-%m-%d %H:%M')}

      口径
      ────
      · 只包含【已记账】凭证。待过账（草稿）与已作废凭证不是账，未导出。
      · 金额单位：元，两位小数。外币分录同时给出原币金额与汇率，本位币为人民币。
      · 科目余额表的期初为区间起始日之前的累计余额。

      文件
      ────
      01_科目表.csv      会计科目（编码/名称/类别/余额方向/是否明细）
      02_凭证序时簿.csv   逐笔分录，按日期与凭证号排序
      03_科目余额表.csv   期初 / 本期借贷发生额 / 期末
      04_会计数据.xml    国标《会计核算软件数据接口》结构

      给会计师事务所的提示
      ────────────────
      各家事务所的导入工具对 XML 的字段与版本要求不完全一致。
      年审前请先拿一份小样试导，需要调整字段的话告诉我们改。
      CSV 三件套是通用格式，事务所一般都能直接收。
    TEXT
  end
end
