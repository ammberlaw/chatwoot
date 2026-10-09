require 'zip'

# 从零生成 .xlsx（OOXML + rubyzip 打包），无需模板、无需额外 gem。
#
# 调用方只负责「数据长什么样」：列宽、行（每格 [值, :s|:n, 样式键]）、合并区域；
# OOXML 那一堆样板收在这里。样式键见 STYLE_INDEX，对应固定的 styles.xml。
#
# 本类是从 Crm::CommissionXlsxService 原样抽出来的，提成表导出和 TikTok 利润表导出共用：
# 改这里会同时影响两处，动之前先用「导出文件 md5 前后一致」验一遍回归。
class XlsxWriter
  STYLE_INDEX = { default: 0, title: 1, header: 2, text: 3, money: 4, rate: 5,
                  subtotal_text: 6, subtotal_money: 7, center: 8 }.freeze

  # col_widths: [字符宽...]；rows: [[[值, :s|:n, 样式键], ...], ...]；
  # merges: ["A1:X1", ...]；sheet_name: 工作表标签名。
  def initialize(col_widths:, rows:, merges: [], sheet_name: 'Sheet1')
    @col_widths = col_widths
    @rows = rows
    @merges = merges
    @sheet_name = sheet_name
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

  # 末列字母（0 起）：调用方算合并区域要用，如 "A1:#{XlsxWriter.col_letter(n - 1)}1"。
  def self.col_letter(idx)
    letters = ''
    n = idx
    loop do
      letters = ((n % 26) + 65).chr + letters
      n = (n / 26) - 1
      break if n.negative?
    end
    letters
  end

  private

  def sheet_xml
    cols = @col_widths.each_with_index.map do |w, i|
      %(<col min="#{i + 1}" max="#{i + 1}" width="#{w}" customWidth="1"/>)
    end.join
    body = @rows.each_with_index.map { |cells, r| row_xml(cells, r + 1) }.join
    merge = @merges.any? ? merge_xml : ''
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <cols>#{cols}</cols>
      <sheetData>#{body}</sheetData>
      #{merge}
      </worksheet>
    XML
  end

  def merge_xml
    %(<mergeCells count="#{@merges.size}">#{@merges.map { |m| %(<mergeCell ref="#{m}"/>) }.join}</mergeCells>)
  end

  def row_xml(cells, rownum)
    tags = cells.each_with_index.filter_map do |(value, type, style_key), c|
      cell_xml(value, type, STYLE_INDEX.fetch(style_key), self.class.col_letter(c), rownum)
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
      <sheets><sheet name="#{xml_escape(@sheet_name)}" sheetId="1" r:id="rId1"/></sheets>
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
