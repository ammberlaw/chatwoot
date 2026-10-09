# TikTok 出库利润表导出：标题 → 表头 → 明细（按店铺分组，每组尾「小计」）→ 全表「总计」。
# OOXML 生成交给共享的 XlsxWriter（与提成表导出同一套样式）。
#
# 列比页面上的多：页面只摆了 9 列看结论，报表要能对账，所以把各项成本/佣金/税费/
# 其它费用和汇率都带上。金额在库里就是 decimal，直接给数值交由 Excel 格式化。
class Tiktok::ProfitXlsxService
  HEADERS = %w[序号 店铺 产品型号 统计月份 时间段 已入账数量 平台负数
               已入账金额 币种 汇率 已入账金额RMB 出厂成本单价 售出总成本
               总毛利 平均单台毛利 平均售卖单价 毛利率
               达人佣金 平台佣金 税费 其它成本 其它成本说明 其它费用合计
               净利润].freeze
  COL_WIDTHS = [5, 18, 18, 10, 14, 10, 9, 13, 7, 9, 14, 13, 13,
                13, 13, 13, 9, 11, 11, 10, 11, 18, 12, 13].freeze

  # 小计/总计只对「可加总」的列求和：数量类与金额类。均价、汇率、毛利率不求和（求和没有意义）。
  SUM_FIELDS = { 5 => :recorded_quantity, 6 => :platform_negative, 10 => :recorded_amount_cny,
                 12 => :total_cost, 13 => :gross_profit, 17 => :influencer_commission,
                 18 => :platform_commission, 19 => :tax, 20 => :other_cost,
                 22 => :extra_expenses_total, 23 => :net_profit }.freeze
  INT_FIELDS = %i[recorded_quantity platform_negative].freeze

  # records: 已按权限收口并筛选好的记录；label: 标题里的范围说明（月份/部门）。
  def initialize(records, label: nil)
    @records = records.to_a
    @label = label
  end

  def to_stream
    XlsxWriter.new(col_widths: COL_WIDTHS, rows: rows,
                   merges: ["A1:#{XlsxWriter.col_letter(HEADERS.size - 1)}1"],
                   sheet_name: '出库利润表').to_stream
  end

  private

  def rows
    out = [title_row, HEADERS.map { |h| [h, :s, :header] }]
    seq = 0
    @records.group_by { |r| r.shop&.name.to_s }.each do |shop_name, items|
      items.each do |item|
        seq += 1
        out << data_row(seq, item)
      end
      out << total_row("#{shop_name.presence || '未归属店铺'} 小计", items)
    end
    out << total_row('总计', @records)
    out
  end

  def title_row
    label = ['TikTok 出库利润表', @label.presence].compact.join(' · ')
    [[label, :s, :title]] + Array.new(HEADERS.size - 1) { ['', :s, :title] }
  end

  def data_row(seq, rec)
    identity_cells(seq, rec) + revenue_cells(rec) + cost_cells(rec)
  end

  # 序号 / 店铺 / 型号 / 月份 / 时间段 / 数量 / 平台负数
  def identity_cells(seq, rec)
    [[seq, :n, :center], [rec.shop&.name, :s, :text], [rec.product_model, :s, :text],
     [rec.stat_month, :s, :center], [rec.period_note, :s, :text],
     [rec.recorded_quantity, :n, :center], [rec.platform_negative, :n, :center]]
  end

  # 入账金额 → 换算 → 成本 → 毛利三件 → 毛利率
  def revenue_cells(rec)
    [num(rec.recorded_amount), [rec.currency, :s, :center], rate(rec.fx_rate),
     num(rec.recorded_amount_cny), num(rec.cost_unit_price), num(rec.total_cost),
     num(rec.gross_profit), num(rec.avg_unit_profit), num(rec.avg_sell_price),
     [margin(rec), :s, :center]]
  end

  # 佣金 / 税费 / 其它成本 / 其它费用 → 净利润
  def cost_cells(rec)
    [num(rec.influencer_commission), num(rec.platform_commission), num(rec.tax),
     num(rec.other_cost), [rec.other_cost_note, :s, :text], num(rec.extra_expenses_total),
     num(rec.net_profit)]
  end

  # 小计 / 总计：只填可加总的列，其余留空。毛利率按该组汇总值重算，不是各行平均。
  def total_row(label, items)
    row = Array.new(HEADERS.size) { ['', :s, :subtotal_text] }
    row[1] = [label, :s, :subtotal_text]
    SUM_FIELDS.each do |idx, field|
      total = items.sum { |i| i.public_send(field).to_d }
      row[idx] = if INT_FIELDS.include?(field)
                   [total.to_i, :n, :subtotal_text]
                 else
                   [total.round(2).to_f, :n, :subtotal_money]
                 end
    end
    row[16] = [group_margin(items), :s, :subtotal_text]
    row
  end

  def num(value)
    value.nil? ? ['', :s, :text] : [value.to_d.round(2).to_f, :n, :money]
  end

  def rate(value)
    value.to_d.zero? ? ['', :s, :text] : [value.to_d.round(4).to_f, :n, :rate]
  end

  # 毛利率 = 总毛利 / 已入账金额RMB（口径同页面）。分母为 0 时不显示，不写 0%。
  def margin(record)
    pct(record.gross_profit, record.recorded_amount_cny)
  end

  def group_margin(items)
    pct(items.sum { |i| i.gross_profit.to_d }, items.sum { |i| i.recorded_amount_cny.to_d })
  end

  def pct(numerator, denominator)
    return '' if denominator.to_d.zero?

    "#{((numerator.to_d / denominator.to_d) * 100).round(1)}%"
  end
end
