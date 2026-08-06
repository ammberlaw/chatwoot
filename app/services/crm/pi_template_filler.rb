# 把 PI 数据填进「你的原始模板」xlsx（lib/pi/pi_template.xlsx），保住 logo/字体/线条/合并 —— 真·1:1。
# 用 ZIP + 字符串改 XML（rubyzip 现成），不重画、不加依赖：
#   · 表头字段改 sharedStrings；数字改单元格；
#   · 明细按项数克隆模板里的「20-21 两行块」，下面各行整体下移，GRAND TOTAL 的 SUM 跟着扩。
require 'zip'

class Crm::PiTemplateFiller
  TEMPLATE = Rails.root.join('lib/pi/pi_template.xlsx')

  SHEET = 'xl/worksheets/sheet1.xml'.freeze
  STRINGS = 'xl/sharedStrings.xml'.freeze

  # 表头字段 → sharedStrings 索引（模板里这些串各自唯一，直接替换其文本）。
  ITEM_TOP = 20 # 模板里明细块起始行（20-21 两行为一项）
  ITEM_ROWS = 2

  def initialize(pi)
    @pi = pi
  end

  def to_stream
    entries = read_template
    # zip 读出的内容是 ASCII-8BIT，而 xlsx 的 XML 是 UTF-8；不强制标注，gsub 注入中文值会报编码不兼容。
    entries[STRINGS] = entries[STRINGS].force_encoding('UTF-8')
    entries[SHEET] = entries[SHEET].force_encoding('UTF-8')
    map = string_map
    entries[STRINGS] = fill_strings(entries[STRINGS], map)
    entries[SHEET] = fill_sheet(entries[SHEET])
    repackage(entries)
  end

  private

  # 各字段的目标 sharedString 索引（见模板 sharedStrings.xml）。
  def string_map
    terms = @pi.terms.to_s.split("\n").map(&:strip).reject(&:empty?)
    {
      6 => @pi.pi_no,
      8 => @pi.pi_date&.strftime('%Y-%m-%d'),
      12 => @pi.attention,
      16 => @pi.buyer_company,
      20 => @pi.buyer_address,
      24 => @pi.buyer_email,
      28 => @pi.buyer_tel,
      32 => @pi.buyer_eori,
      14 => @pi.port_of_shipment,
      18 => @pi.port_of_destination,
      22 => @pi.country_of_origin,
      26 => @pi.currency,
      30 => @pi.shipping_method,
      43 => @pi.shipping_cost_label,
      46 => terms[0],
      47 => (terms.length > 2 ? terms[1..].join("\n") : terms[1]),
      58 => "ISSUED BY\n#{@pi.issued_by}"
    }
  end

  def read_template
    entries = {}
    Zip::File.open(TEMPLATE) do |zip|
      zip.each do |e|
        next if e.directory?

        entries[e.name] = e.get_input_stream.read
      end
    end
    entries
  end

  # 替换第 idx 个 <si> 的文本（nil 保留原值不动）。
  def fill_strings(xml, map)
    idx = -1
    xml.gsub(%r{<si>.*?</si>}m) do |si|
      idx += 1
      val = map[idx]
      val.nil? ? si : "<si>#{t_node(val)}</si>"
    end
  end

  def t_node(value)
    %(<t xml:space="preserve">#{xml_escape(value)}</t>)
  end

  def fill_sheet(xml)
    items = @pi.pi_items.to_a
    items = [nil] if items.empty? # 至少保留一行（空）
    delta = (items.length - 1) * ITEM_ROWS

    data = xml[%r{<sheetData>.*?</sheetData>}m]
    rows = data.scan(%r{<row r="(\d+)".*?</row>}m).flatten.map(&:to_i)

    head = rows_between(data, rows.min, ITEM_TOP - 1)
    tail_start = ITEM_TOP + ITEM_ROWS # 22
    tail = rows_between(data, tail_start, rows.max)

    item_region = items.each_with_index.map { |it, i| item_block(it, ITEM_TOP + i * ITEM_ROWS) }.join
    tail = shift_tail(tail, delta) if delta.positive?
    # 运费金额（原 H22，位于 tail）——移位后由 shift 处理行号，这里先按原行号写值。
    new_data = "<sheetData>#{head}#{item_region}#{tail}</sheetData>"
    new_data = set_cell_value(new_data, "H#{22 + delta}", 23, @pi.shipping_cost_micros)

    xml = xml.sub(%r{<sheetData>.*?</sheetData>}m, new_data)
    rebuild_merges(xml, items.length, delta)
  end

  # 抽取 [from,to] 行的 XML 串。
  def rows_between(data, from, to)
    (from..to).map do |r|
      data[%r{<row r="#{r}"[^>]*>.*?</row>}m].to_s
    end.join
  end

  # 生成一项的两行块（首行放数据，次行空；文本用 inlineStr，样式沿用模板 s 值）。
  def item_block(item, top)
    bottom = top + 1
    model = item ? xml_escape(item.model) : ''
    desc = item ? xml_escape(item.description) : ''
    qty = item&.quantity
    price = item&.unit_price_micros
    <<~ROW.delete("\n")
      <row r="#{top}" ht="38" customHeight="1" spans="1:8">
      <c r="A#{top}" s="19" t="inlineStr"><is><t xml:space="preserve">#{model}</t></is></c>
      <c r="B#{top}" s="20"/><c r="C#{top}" s="20"/>
      <c r="D#{top}" s="19" t="inlineStr"><is><t xml:space="preserve">#{desc}</t></is></c>
      <c r="E#{top}" s="19"/>
      <c r="F#{top}" s="19">#{num_v(qty)}</c>
      <c r="G#{top}" s="21">#{num_v(micros_to_f(price))}</c>
      <c r="H#{top}" s="21"><f>F#{top}*G#{top}</f></c>
      </row>
      <row r="#{bottom}" ht="38" customHeight="1" spans="1:8">
      <c r="A#{bottom}" s="19"/><c r="B#{bottom}" s="20"/><c r="C#{bottom}" s="20"/>
      <c r="D#{bottom}" s="19"/><c r="E#{bottom}" s="19"/><c r="F#{bottom}" s="19"/>
      <c r="G#{bottom}" s="21"/><c r="H#{bottom}" s="21"/>
      </row>
    ROW
  end

  # tail 段所有行 >=22，行号/单元格引用整体 +delta；公式内 >=22 的引用也 +delta（H20 保持）。
  def shift_tail(tail, delta)
    shifted = tail.gsub(/r="([A-Z]*)(\d+)"/) { %(r="#{Regexp.last_match(1)}#{Regexp.last_match(2).to_i + delta}") }
    shifted.gsub(%r{<f>(.*?)</f>}m) do
      inner = Regexp.last_match(1).gsub(/([A-Z]+)(\d+)/) do
        col = Regexp.last_match(1)
        n = Regexp.last_match(2).to_i
        "#{col}#{n >= 22 ? n + delta : n}"
      end
      "<f>#{inner}</f>"
    end
  end

  # 设置某单元格的数值（保留样式 s）；micros→元。
  def set_cell_value(data, ref, style, micros)
    v = micros.nil? ? '' : "<v>#{micros_to_f(micros)}</v>"
    data.sub(%r{<c r="#{ref}"[^>]*?(?:/>|>.*?</c>)}m, %(<c r="#{ref}" s="#{style}">#{v}</c>))
  end

  # 重建 mergeCells：表头合并保留；明细块合并按项数复制；>=22 的合并 +delta。
  def rebuild_merges(xml, item_count, delta)
    block = xml[%r{<mergeCells[^>]*>(.*?)</mergeCells>}m, 1]
    return xml unless block

    refs = block.scan(/ref="([^"]+)"/).flatten
    kept = []
    refs.each do |ref|
      r1, r2 = ref.scan(/\d+/).map(&:to_i)
      if r2 <= ITEM_TOP - 1
        kept << ref
      elsif r1 >= 22
        kept << shift_ref(ref, delta)
      end
      # 20-21 的明细块合并丢弃，改由下面按项数重建
    end
    item_count.times do |i|
      off = i * ITEM_ROWS
      %w[A A B C D E F F G G H H].each_slice(2) do |c1, c2|
        kept << "#{c1}#{ITEM_TOP + off}:#{c2}#{ITEM_TOP + 1 + off}"
      end
    end
    new_block = %(<mergeCells count="#{kept.length}">#{kept.map { |r| %(<mergeCell ref="#{r}"/>) }.join}</mergeCells>)
    xml.sub(%r{<mergeCells[^>]*>.*?</mergeCells>}m, new_block)
  end

  def shift_ref(ref, delta)
    ref.gsub(/([A-Z]+)(\d+)/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).to_i + delta}" }
  end

  def repackage(entries)
    buffer = Zip::OutputStream.write_buffer do |out|
      entries.each do |name, content|
        out.put_next_entry(name)
        out.write(content)
      end
    end
    buffer.rewind
    buffer
  end

  def num_v(value)
    value.nil? ? '' : "<v>#{value}</v>"
  end

  def micros_to_f(micros)
    return nil if micros.nil?

    f = micros / 1_000_000.0
    (f % 1).zero? ? f.to_i : f
  end

  def xml_escape(value)
    value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '&#10;')
  end
end
