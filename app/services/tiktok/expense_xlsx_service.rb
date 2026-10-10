# TikTok 支出台账导出：标题 → 表头 → 明细（按部门分组，每组尾「小计」）→ 全表「总计」。
# 排版与出库利润表同一套（共享 XlsxWriter），财务两张表对着看不用换脑子。
#
# 只对「人民币金额」求和：原币金额混着 CNY/PHP/USD/EUR，加起来没有意义；
# 汇率同理不求和。所以小计/总计只填 amount_cny 那一列。
class Tiktok::ExpenseXlsxService
  HEADERS = %w[序号 日期 部门 店铺 费用类别 费用科目
               原币金额 币种 汇率 金额RMB 备注 录入人].freeze
  COL_WIDTHS = [5, 12, 14, 16, 12, 20, 13, 7, 10, 14, 28, 12].freeze

  AMOUNT_CNY_COL = 9 # 「金额RMB」列下标，小计/总计只加这一列

  # records: 已按权限收口并筛选好的记录；label: 标题里的范围说明（月份/部门）。
  def initialize(records, label: nil)
    @records = records.to_a
    @label = label
  end

  def to_stream
    XlsxWriter.new(col_widths: COL_WIDTHS, rows: rows,
                   merges: ["A1:#{XlsxWriter.col_letter(HEADERS.size - 1)}1"],
                   sheet_name: '支出台账').to_stream
  end

  private

  def rows
    out = [title_row, HEADERS.map { |h| [h, :s, :header] }]
    seq = 0
    @records.group_by { |r| r.department&.name.to_s }.each do |dept_name, items|
      items.each do |item|
        seq += 1
        out << data_row(seq, item)
      end
      out << total_row("#{dept_name.presence || '未归属部门'} 小计", items)
    end
    out << total_row('总计', @records)
    out
  end

  def title_row
    label = ['TikTok 支出台账', @label.presence].compact.join(' · ')
    [[label, :s, :title]] + Array.new(HEADERS.size - 1) { ['', :s, :title] }
  end

  def data_row(seq, rec)
    [
      [seq, :n, :center],
      [rec.expense_date&.to_s, :s, :center],
      [rec.department&.name, :s, :text],
      [rec.shop&.name, :s, :text],
      [rec.category, :s, :center],
      [rec.subject, :s, :text],
      num(rec.amount),
      [rec.currency, :s, :center],
      rate(rec.fx_rate),
      num(rec.amount_cny),
      [rec.remark, :s, :text],
      [rec.creator&.name, :s, :text]
    ]
  end

  # 小计 / 总计：只填金额RMB，其余留空（原币与汇率跨币种求和没有意义）。
  def total_row(label, items)
    row = Array.new(HEADERS.size) { ['', :s, :subtotal_text] }
    row[2] = [label, :s, :subtotal_text]
    row[AMOUNT_CNY_COL] =
      [items.sum { |i| i.amount_cny.to_d }.round(2).to_f, :n, :subtotal_money]
    row
  end

  def num(value) = [value.to_d.round(2).to_f, :n, :money]
  def rate(value) = [value.to_d.round(6).to_f, :n, :rate]
end
