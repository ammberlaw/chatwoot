require 'builder'

# 审计数据包里的 XML：按国标《会计核算软件数据接口》的结构组织
# （企业信息 → 科目表 → 凭证表，凭证下挂分录）。
#
# 标签名一律走 `tag!('中文')` 而不是 `builder.中文`——后者是 method_missing，
# 中文方法名既过不了 rubocop，出错时也很难查。
#
# ⚠️ 各家事务所的导入工具对字段与版本要求不一致，年审前先拿小样试导一次。
class Erp::AuditXmlBuilder
  def initialize(account, exporter)
    @account = account
    @exporter = exporter
  end

  def build(from:, to:, ledger_accounts:, lines:)
    xml = Builder::XmlMarkup.new(indent: 2)
    xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
    xml.tag!('会计数据') do
      company(xml, from, to)
      xml.tag!('科目表') { ledger_accounts.each { |item| account_node(xml, item) } }
      xml.tag!('凭证表') { lines.group_by(&:voucher).each { |voucher, rows| voucher_node(xml, voucher, rows) } }
    end
  end

  private

  def company(xml, from, to)
    xml.tag!('企业信息') do
      xml.tag!('企业名称', @account.name)
      xml.tag!('本位币', 'CNY')
      xml.tag!('会计期间起', from.to_s)
      xml.tag!('会计期间止', to.to_s)
      xml.tag!('导出时间', Time.current.iso8601)
      xml.tag!('数据来源', 'Wintouch-ERP')
    end
  end

  def account_node(xml, item)
    xml.tag!('科目') do
      xml.tag!('科目编码', item.code)
      xml.tag!('科目名称', item.name)
      xml.tag!('科目类别', Erp::LedgerAccount::CATEGORY_LABELS[item.category])
      xml.tag!('余额方向', direction_label(item.direction))
      xml.tag!('是否明细', item.is_group? ? '否' : '是')
    end
  end

  def voucher_node(xml, voucher, rows)
    xml.tag!('凭证') do
      xml.tag!('凭证号', voucher.voucher_no)
      xml.tag!('凭证日期', voucher.voucher_date.to_s)
      xml.tag!('会计期间', voucher.period)
      xml.tag!('凭证摘要', voucher.summary)
      xml.tag!('制单人', @exporter.person(voucher.prepared_by))
      xml.tag!('记账人', @exporter.person(voucher.posted_by))
      xml.tag!('分录表') { rows.each { |line| entry_node(xml, line) } }
    end
  end

  def entry_node(xml, line)
    xml.tag!('分录') { entry_fields(line).each { |tag, value| xml.tag!(tag, value) } }
  end

  def entry_fields(line)
    {
      '摘要' => line.summary,
      '科目编码' => line.ledger_account.code,
      '方向' => direction_label(line.direction),
      '本位币金额' => @exporter.yuan(line.base_amount_micros),
      '币种' => line.currency,
      '汇率' => line.exchange_rate.to_s,
      '原币金额' => @exporter.yuan(line.amount_micros),
      '客户' => line.crm_customer&.name,
      '供应商' => line.mes_supplier&.name
    }
  end

  def direction_label(direction)
    direction == Erp::VoucherLine::DEBIT ? '借' : '贷'
  end
end
