require 'zip'

# 提成表 Excel 导出：从零生成 .xlsx（OOXML，rubyzip 打包），无需模板。
# 优化版式：标题 → 表头 → 按产品品类分组（每组尾「小计」）→ 全表「总计」。
# 金额列存微分（×1_000_000），导出时还原为真实数值，交由 Excel 数字格式显示两位小数。
class Crm::CommissionXlsxService
  # 表头（与前端明细表一致）；nil 品类归到「未分类」。
  HEADERS = ['序号', '产品品类', '国家', '客户名称', 'PI号', '订单状态', '订单金额', '币种', '运费',
             '收款金额', '汇率', '收款额RMB', '销售额RMB', '汇款途径', '到款日期', '产品', '备注',
             '对公', '税点', '提成基数RMB', '提成点(%)', '提成工资'].freeze
  COL_WIDTHS = [5, 12, 10, 22, 20, 10, 12, 7, 10, 12, 8, 12, 12, 16, 12, 24, 16, 6, 6, 14, 10, 14].freeze
  MONEY_COLS = [6, 8, 9, 11, 12].freeze # 0-based：订单金额/运费/收款金额/收款额RMB/销售额RMB
  RATE_COL = 10
  BASE_COL = 19 # 提成基数RMB
  SALARY_COL = 21 # 提成工资

  # 关联销售订单状态 → 中文（与前端一致，只读展示）。
  ORDER_STATUS_LABEL = { 'PENDING_CONFIRMATION' => '待确认', 'IN_PRODUCTION' => '生产中',
                         'PENDING_SHIPMENT' => '待出货', 'SHIPPED' => '已出货',
                         'COMPLETED' => '已完成', 'CANCELLED' => '已取消' }.freeze

  def initialize(sheet)
    @sheet = sheet
    @rates = Crm::CommissionRate.map_for(sheet.account)
  end

  def to_stream
    buffer = Zip::OutputStream.write_buffer do |zip|
      { '[Content_Types].xml' => content_types, '_rels/.rels' => root_rels,
        'xl/workbook.xml' => workbook, 'xl/_rels/workbook.xml.rels' => workbook_rels,
        'xl/styles.xml' => styles, 'xl/worksheets/sheet1.xml' => sheet_xml }.each do |path, xml|
        zip.put_next_entry(path)
        zip.write(xml)
      end
    end
    buffer.rewind
    buffer
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
      money(item.received_amount_micros), rate(item.exchange_rate), money(item.received_rmb_micros),
      money(item.sales_rmb_micros), [item.payment_channel, :s, :text], [fmt_date(item.payment_date), :s, :center],
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
    row[11] = subtotal_money(items, :received_rmb_micros)
    row[12] = subtotal_money(items, :sales_rmb_micros)
    row[SALARY_COL] = subtotal_salary(items)
    row
  end

  def grand_total_row
    all = @sheet.items.to_a
    row = Array.new(HEADERS.size) { ['', :s, :subtotal_text] }
    row[1] = ['总计', :s, :subtotal_text]
    row[8] = subtotal_money(all, :shipping_micros)
    row[11] = subtotal_money(all, :received_rmb_micros)
    row[12] = subtotal_money(all, :sales_rmb_micros)
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

  # ── OOXML 生成 ─────────────────────────────────────────────
  STYLE_INDEX = { default: 0, title: 1, header: 2, text: 3, money: 4, rate: 5,
                  subtotal_text: 6, subtotal_money: 7, center: 8 }.freeze

  def sheet_xml
    data = rows
    cols = COL_WIDTHS.each_with_index.map do |w, i|
      %(<col min="#{i + 1}" max="#{i + 1}" width="#{w}" customWidth="1"/>)
    end.join
    body = data.each_with_index.map { |cells, r| row_xml(cells, r + 1) }.join
    merge = %(<mergeCells count="1"><mergeCell ref="A1:#{col_letter(HEADERS.size - 1)}1"/></mergeCells>)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <cols>#{cols}</cols>
      <sheetData>#{body}</sheetData>
      #{merge}
      </worksheet>
    XML
  end

  def row_xml(cells, rownum)
    tags = cells.each_with_index.filter_map do |(value, type, style_key), c|
      cell_xml(value, type, STYLE_INDEX.fetch(style_key), col_letter(c), rownum)
    end.join
    %(<row r="#{rownum}">#{tags}</row>)
  end

  def cell_xml(value, type, style, col, rownum)
    ref = "#{col}#{rownum}"
    if type == :n && value != '' && !value.nil?
      %(<c r="#{ref}" s="#{style}"><v>#{value}</v></c>)
    elsif value.to_s.empty?
      %(<c r="#{ref}" s="#{style}"/>)
    else
      %(<c r="#{ref}" s="#{style}" t="inlineStr"><is><t xml:space="preserve">#{xml_escape(value)}</t></is></c>)
    end
  end

  def col_letter(idx)
    letters = ''
    n = idx
    loop do
      letters = ((n % 26) + 65).chr + letters
      n = n / 26 - 1
      break if n < 0
    end
    letters
  end

  def xml_escape(str)
    str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  def content_types
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      </Types>
    XML
  end

  def root_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
      </Relationships>
    XML
  end

  def workbook
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="#{xml_escape(@sheet.period_month.strftime('%-m月'))}" sheetId="1" r:id="rId1"/></sheets>
      </workbook>
    XML
  end

  def workbook_rels
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      </Relationships>
    XML
  end

  # 字体/填充/边框/数字格式与 cellXfs（顺序需与 STYLE_INDEX 对应）。
  def styles
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <numFmts count="2">
      <numFmt numFmtId="164" formatCode="#,##0.00"/>
      <numFmt numFmtId="165" formatCode="0.0000"/>
      </numFmts>
      <fonts count="3">
      <font><sz val="11"/><name val="宋体"/></font>
      <font><b/><sz val="11"/><name val="宋体"/></font>
      <font><b/><sz val="14"/><name val="宋体"/></font>
      </fonts>
      <fills count="4">
      <fill><patternFill patternType="none"/></fill>
      <fill><patternFill patternType="gray125"/></fill>
      <fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill>
      <fill><patternFill patternType="solid"><fgColor rgb="FFF2F2F2"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="2">
      <border><left/><right/><top/><bottom/><diagonal/></border>
      <border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>
      </borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="9">
      <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
      <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
      <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
      <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
      <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyNumberFormat="1"/>
      <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyNumberFormat="1"/>
      <xf numFmtId="0" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
      <xf numFmtId="164" fontId="1" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1"/>
      <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment horizontal="center"/></xf>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      </styleSheet>
    XML
  end
end
