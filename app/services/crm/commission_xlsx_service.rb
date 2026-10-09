# 提成表 Excel 导出：从零生成 .xlsx（OOXML，rubyzip 打包），无需模板。
# 优化版式：标题 → 表头 → 按产品品类分组（每组尾「小计」）→ 全表「总计」。
# 金额列存微分（×1_000_000），导出时还原为真实数值，交由 Excel 数字格式显示两位小数。
class Crm::CommissionXlsxService
  # 表头（与前端明细表一致）；nil 品类归到「未分类」。
  HEADERS = ['序号', '产品品类', '国家', '客户名称', 'PI号', '订单状态', '订单金额', '币种', '运费',
             '货代实收运费', '收款金额', '汇率', '收款额RMB', '销售额RMB', '运费差额', '汇款途径', '到款日期', '产品', '备注',
             '对公', '税点', '提成基数RMB', '提成点(%)', '提成工资'].freeze
  COL_WIDTHS = [5, 12, 10, 22, 20, 10, 12, 7, 10, 14, 12, 8, 12, 12, 12, 16, 12, 24, 16, 6, 6, 14, 10, 14].freeze
  MONEY_COLS = [6, 8, 9, 10, 12, 13, 14].freeze # 0-based：订单金额/运费/货代实收运费/收款金额/收款额RMB/销售额RMB/运费差额
  RATE_COL = 11
  BASE_COL = 21 # 提成基数RMB
  SALARY_COL = 23 # 提成工资

  # 关联销售订单状态 → 中文（与前端一致，只读展示）。
  ORDER_STATUS_LABEL = { 'PENDING_CONFIRMATION' => '待确认', 'IN_PRODUCTION' => '生产中',
                         'PENDING_SHIPMENT' => '待出货', 'SHIPPED' => '已出货',
                         'COMPLETED' => '已完成', 'CANCELLED' => '已取消' }.freeze

  def initialize(sheet)
    @sheet = sheet
    @rates = Crm::CommissionRate.map_for(sheet.account)
  end

  def to_stream
    XlsxWriter.new(col_widths: COL_WIDTHS, rows: rows,
                   merges: ["A1:#{XlsxWriter.col_letter(HEADERS.size - 1)}1"],
                   sheet_name: @sheet.period_month.strftime('%-m月')).to_stream
  end

  private

  # ── 数据行装配 ──────────────────────────────────────────────
  # 返回 [row_cells...]；每个 cell = [value, :s|:n, style_key]。
  def rows
    out = []
    out << title_row
    out << HEADERS.map { |h| [h, :s, :header] }

    seq = 0
    grouped.each do |category, items|
      items.each do |item|
        seq += 1
        out << data_row(seq, item)
      end
      out << subtotal_row(category, items)
    end
    out << grand_total_row
    out
  end

  def title_row
    label = "#{owner_name} #{@sheet.period_month.strftime('%Y年%-m月')}业务计算提成"
    [[label, :s, :title]] + Array.new(HEADERS.size - 1) { ['', :s, :title] }
  end

  def data_row(seq, item)
    pct = @rates[item.product_category]
    [
      [seq, :n, :center], [item.product_category.presence || '未分类', :s, :text],
      [item.country, :s, :center], [item.customer_name, :s, :text], [item.order_no, :s, :text],
      [ORDER_STATUS_LABEL[item.sales_order&.status], :s, :center],
      money(item.order_amount_micros), [item.currency, :s, :center], money(item.shipping_micros),
      money(item.forwarder_shipping_micros),
      money(item.received_amount_micros), rate(item.exchange_rate), money(item.received_rmb_micros),
      money(item.sales_rmb_micros), money(item.freight_diff_micros),
      [item.payment_channel, :s, :text], [fmt_date(item.payment_date), :s, :center],
      [item.product, :s, :text], [item.remark, :s, :text],
      [item.is_public_receipt ? '是' : '', :s, :center],
      [item.is_public_receipt ? "#{item.tax_rate}%" : '', :s, :center], money(item.commission_base_micros),
      pct.nil? ? ['', :s, :center] : [pct.to_f.round(2), :n, :money], money(item.commission_salary_micros(pct))
    ]
  end

  def subtotal_row(category, items)
    row = Array.new(HEADERS.size) { ['', :s, :subtotal_text] }
    row[1] = ["#{category.presence || '未分类'} 小计", :s, :subtotal_text]
    row[8] = subtotal_money(items, :shipping_micros)
    row[9] = subtotal_money(items, :forwarder_shipping_micros)
    row[12] = subtotal_money(items, :received_rmb_micros)
    row[13] = subtotal_money(items, :sales_rmb_micros)
    row[14] = subtotal_money(items, :freight_diff_micros)
    row[SALARY_COL] = subtotal_salary(items)
    row
  end

  def grand_total_row
    all = @sheet.items.to_a
    row = Array.new(HEADERS.size) { ['', :s, :subtotal_text] }
    row[1] = ['总计', :s, :subtotal_text]
    row[8] = subtotal_money(all, :shipping_micros)
    row[9] = subtotal_money(all, :forwarder_shipping_micros)
    row[12] = subtotal_money(all, :received_rmb_micros)
    row[13] = subtotal_money(all, :sales_rmb_micros)
    row[14] = subtotal_money(all, :freight_diff_micros)
    row[SALARY_COL] = subtotal_salary(all)
    row
  end

  # 提成工资小计：逐行按品类点位算后求和（品类没配点位的行记 0）。
  def subtotal_salary(items)
    total = items.sum { |i| i.commission_salary_micros(@rates[i.product_category]).to_i }
    [(total.to_f / 1_000_000).round(2), :n, :subtotal_money]
  end

  # 按产品品类分组，保留出现顺序。
  def grouped
    @sheet.items.to_a.group_by(&:product_category)
  end

  def money(micros)
    micros.nil? ? ['', :s, :text] : [(micros.to_f / 1_000_000).round(2), :n, :money]
  end

  def subtotal_money(items, field)
    total = items.sum { |i| i.public_send(field).to_i }
    [(total.to_f / 1_000_000).round(2), :n, :subtotal_money]
  end

  def rate(value)
    value.nil? ? ['', :s, :center] : [value.to_f.round(4), :n, :rate]
  end

  def fmt_date(value)
    value&.strftime('%Y-%m-%d')
  end

  def owner_name
    @sheet.owner&.crm_display_name.to_s
  end
end
