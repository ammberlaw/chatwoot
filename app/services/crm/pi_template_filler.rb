# 把 PI 数据填进「你的原始模板」xlsx（lib/pi/pi_template.xlsx），保住 logo/字体/线条/合并 —— 真·1:1。
# 用 ZIP + 字符串改 XML（rubyzip 现成），不重画、不加依赖：
#   · 表头字段改 sharedStrings；数字改单元格；
#   · 明细按项数克隆模板里的「20-21 两行块」，下面各行整体下移，GRAND TOTAL 的 SUM 跟着扩。
require 'zip'

class Crm::PiTemplateFiller
  TEMPLATE = Rails.root.join('lib/pi/pi_template.xlsx')

  SHEET = 'xl/worksheets/sheet1.xml'.freeze
  STRINGS = 'xl/sharedStrings.xml'.freeze
  DRAWING = 'xl/drawings/drawing1.xml'.freeze
  DRAWING_RELS = 'xl/drawings/_rels/drawing1.xml.rels'.freeze
  CONTENT_TYPES = '[Content_Types].xml'.freeze
  IMAGE_REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze

  # PICTURE 格尺寸（B:C 两列各宽14≈98px × 2行各38pt），用于产品图等比缩放居中。EMU 单位。
  EMU_PER_PX = 9525
  EMU_PER_PT = 12_700
  PIC_CELL_W = 2 * 98 * EMU_PER_PX  # 两列各宽14≈98px
  PIC_CELL_H = 2 * 38 * EMU_PER_PT   # 两行 × 38pt
  PIC_PAD = 19_050                   # 四周内边距（约2px）

  # 卖方抬头里的公司公用网址（Email 行尾），业务员个人只填邮箱，其余保持全公司一致。
  SELLER_WEB = 'www.wintouchcn.com   |   https://wintouchtech.com'.freeze

  # 公司抬头预设：建 PI 选一个，导出时公司名/地址/银行整块按此填。新增主体在此加一项即可。
  # 顶部公司地址(address)两主体暂共用东莞办公地址；如需各自不同，改对应 address 即可。
  FOOTER_SUFFIX = '  •  Thank you for your business'.freeze
  DONGGUAN_ADDRESS = 'Yonghui Hengwang Zhigu, 3rd–4th Floor, No. 2 Lianfeng New Road Dongguan, Guangdong, China'.freeze
  COMPANY_HEADERS = {
    'HK_WINTOUCH' => {
      name: 'HONG KONG WINTOUCH GROUP CO., LIMITED',
      address: DONGGUAN_ADDRESS,
      beneficiary: 'HONG KONG WINTOUCH GROUP CO., LIMITED',
      account_no: 'A/C 846210294378',
      bank_code: '009',
      branch_code: '846',
      bank: 'China Construction Bank (Asia) Co., Ltd',
      swift: 'CCBQHKAX',
      bank_address: '20/F CCB Centre, 18 Wang Chiu Road, Kowloon Bay, Kowloon, Hong Kong',
      footer: 'HONG KONG WINTOUCH GROUP CO., LIMITED'
    },
    'DG_LIONTEK' => {
      name: 'DONGGUAN LIONTEK TECHNOLOGY CO., LTD',
      address: DONGGUAN_ADDRESS,
      beneficiary: 'Dongguan Liontek Technology Co., Ltd.',
      account_no: 'A/C 44050177780800003217',
      bank: 'China Construction Bank, Dongguan City Daling Shan Branch',
      swift: 'PCBCCNBJGDD',
      bank_address: 'Daling Shan Town, Dongguan City, Guangdong Province, China',
      footer: 'Dongguan Liontek Technology Co., Ltd.'
    }
  }.freeze
  DEFAULT_HEADER_KEY = 'HK_WINTOUCH'.freeze

  # 供前端下拉：[{ key, name }]。抬头是稳定主体，前端选项以此为唯一来源。
  def self.header_options
    COMPANY_HEADERS.map { |key, h| { key: key, name: h[:name] } }
  end

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
    embed_item_pictures(entries)
    repackage(entries)
  end

  private

  # 各字段的目标 sharedString 索引（见模板 sharedStrings.xml）。
  def string_map
    terms = @pi.terms.to_s.split("\n").map(&:strip).reject(&:empty?)
    h = header
    {
      # 公司抬头主体（按所选抬头填：公司名/顶部地址/银行块/页脚；SWIFT 值在 fill_sheet 里写 H 列）。
      0 => h[:name],
      3 => h[:address],
      50 => h[:beneficiary],
      52 => account_line(h),
      54 => h[:bank],
      57 => h[:bank_address],
      59 => "#{h[:footer]}#{FOOTER_SUFFIX}",
      # 卖方抬头（按业务员预录带入的 PI 快照填；姓名复用 issued_by，网址公用静态）。
      1 => "Contact: #{@pi.issued_by}   |   Mobile: #{@pi.seller_mobile}",
      2 => "Email: #{@pi.seller_email}   |   #{SELLER_WEB}",
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

  # 所选公司抬头（无效/空则回落默认主体，即模板原有的香港抬头）。
  def header
    COMPANY_HEADERS[@pi.company_header] || COMPANY_HEADERS[DEFAULT_HEADER_KEY]
  end

  # 账号行：账号 + （有则）Bank Code / Branch Code，同一行并排（香港才有行号）。
  def account_line(h)
    parts = [h[:account_no]]
    parts << "Bank Code: #{h[:bank_code]}" if h[:bank_code].present?
    parts << "Branch Code: #{h[:branch_code]}" if h[:branch_code].present?
    parts.join('   ·   ')
  end

  # 把每个明细上传的产品图嵌进 xlsx 的 PICTURE 列（B:C 合并格）。
  # 复用模板现有 drawing1（原本只锚了左上角 LOGO）：往里追加每张图的锚点 + media + 关系，
  # 并确保 [Content_Types] 声明了对应图片扩展名。无图的明细跳过。
  def embed_item_pictures(entries)
    items = @pi.pi_items.to_a
    anchors = +''
    rels = +''
    exts = []
    items.each_with_index do |item, i|
      next unless item.picture.attached?

      ext = picture_ext(item)
      bytes = item.picture.download
      exts << ext
      entries["xl/media/pi_item_#{i}.#{ext}"] = bytes
      rels << %(<Relationship Id="rIdPi#{i}" Type="#{IMAGE_REL_TYPE}" Target="../media/pi_item_#{i}.#{ext}"/>)
      anchors << item_anchor(i, image_size(bytes))
    rescue StandardError => e
      Rails.logger.warn("[Crm::PiTemplate] item=#{item.id} picture embed failed: #{e.message}")
    end
    return if anchors.empty?

    entries[DRAWING] = entries[DRAWING].force_encoding('UTF-8').sub('</xdr:wsDr>', "#{anchors}</xdr:wsDr>")
    entries[DRAWING_RELS] = entries[DRAWING_RELS].force_encoding('UTF-8').sub('</Relationships>', "#{rels}</Relationships>")
    entries[CONTENT_TYPES] = ensure_content_types(entries[CONTENT_TYPES].force_encoding('UTF-8'), exts.uniq)
  end

  # 第 i 个明细的图片锚点：定位到该明细两行块的 PICTURE 列（B:C）。行号 0 基，不受 tail 位移影响
  # （明细区在 ITEM_TOP 起、位于 tail 之前）。按图片真实宽高等比缩放、格内居中，不拉伸变形；
  # 拿不到尺寸时（少见格式）回退填满。
  def item_anchor(i, size)
    top0 = (ITEM_TOP - 1) + i * ITEM_ROWS
    return fill_anchor(i, top0) unless size

    w = size[0] * EMU_PER_PX
    h = size[1] * EMU_PER_PX
    scale = [(PIC_CELL_W - 2 * PIC_PAD).to_f / w, (PIC_CELL_H - 2 * PIC_PAD).to_f / h].min
    fw = (w * scale).round
    fh = (h * scale).round
    off_x = ((PIC_CELL_W - fw) / 2).round
    off_y = ((PIC_CELL_H - fh) / 2).round
    <<~XML.delete("\n")
      <xdr:oneCellAnchor>
      <xdr:from><xdr:col>1</xdr:col><xdr:colOff>#{off_x}</xdr:colOff><xdr:row>#{top0}</xdr:row><xdr:rowOff>#{off_y}</xdr:rowOff></xdr:from>
      <xdr:ext cx="#{fw}" cy="#{fh}"/>
      <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="#{1000 + i}" name="pi_item_#{i}"/>
      <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>
      <xdr:blipFill><a:blip r:embed="rIdPi#{i}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
      <xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="#{fw}" cy="#{fh}"/></a:xfrm>
      <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>
      <xdr:clientData/></xdr:oneCellAnchor>
    XML
  end

  # 回退：拿不到图片尺寸时按两格填满（会拉伸，仅少见格式走到）。
  def fill_anchor(i, top0)
    <<~XML.delete("\n")
      <xdr:twoCellAnchor editAs="oneCell">
      <xdr:from><xdr:col>1</xdr:col><xdr:colOff>19050</xdr:colOff><xdr:row>#{top0}</xdr:row><xdr:rowOff>19050</xdr:rowOff></xdr:from>
      <xdr:to><xdr:col>3</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>#{top0 + ITEM_ROWS}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
      <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="#{1000 + i}" name="pi_item_#{i}"/>
      <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>
      <xdr:blipFill><a:blip r:embed="rIdPi#{i}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
      <xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>
      <xdr:clientData/></xdr:twoCellAnchor>
    XML
  end

  # 从图片字节读像素宽高（PNG/JPEG，不引外部依赖）；无法解析返回 nil。
  def image_size(bytes)
    b = bytes.b
    return [b[16, 4].unpack1('N'), b[20, 4].unpack1('N')] if b[0, 8] == "\x89PNG\r\n\x1a\n".b

    jpeg_size(b)
  rescue StandardError
    nil
  end

  SOF_MARKERS = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF].freeze

  def jpeg_size(b)
    i = 2
    len = b.bytesize
    while i < len - 8
      return nil unless b.getbyte(i) == 0xFF

      marker = b.getbyte(i + 1)
      i += 2
      next if marker == 0xD8 || marker == 0xD9 || (0xD0..0xD7).cover?(marker)

      seg = (b.getbyte(i) << 8) + b.getbyte(i + 1)
      return [(b.getbyte(i + 5) << 8) + b.getbyte(i + 6), (b.getbyte(i + 3) << 8) + b.getbyte(i + 4)] if SOF_MARKERS.include?(marker)

      i += seg
    end
    nil
  end

  def picture_ext(item)
    ct = item.picture.content_type.to_s.downcase
    return 'png' if ct.include?('png')
    return 'jpeg' if ct.include?('jpeg') || ct.include?('jpg')
    return 'gif' if ct.include?('gif')

    (item.picture.filename.extension.presence || 'png').downcase
  end

  # 确保图片扩展名在 [Content_Types] 有 Default 声明（png 模板已含）。
  def ensure_content_types(xml, exts)
    exts.each do |ext|
      next if xml.include?(%(Extension="#{ext}"))

      ct = %w[jpeg jpg].include?(ext) ? 'image/jpeg' : "image/#{ext}"
      xml = xml.sub('</Types>', %(<Default Extension="#{ext}" ContentType="#{ct}"/></Types>))
    end
    xml
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
    # SWIFT 值不在 sharedStrings（模板里是 H32 的字面值），随明细行数位移后单独覆盖写入。
    new_data = set_cell_str(new_data, "H#{32 + delta}", 35, header[:swift])

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

  # 设置某单元格的文本值（inlineStr，保留样式 s）——用于不在 sharedStrings 的字面值格（如 SWIFT）。
  def set_cell_str(data, ref, style, value)
    cell = %(<c r="#{ref}" s="#{style}" t="inlineStr"><is>#{t_node(value)}</is></c>)
    data.sub(%r{<c r="#{ref}"[^>]*?(?:/>|>.*?</c>)}m, cell)
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
