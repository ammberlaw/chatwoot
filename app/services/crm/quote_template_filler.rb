# 把报价数据填进公司原始模板（lib/quote/quote_template.xlsx 的 Quotation 表），保住 logo/字体/线条/合并 —— 真·1:1。
# 用 ZIP + 字符串改 XML（rubyzip 现成），不重画、不加依赖：
#   · 表头/买方值写进模板既有空格（inlineStr，保留原样式）；
#   · 明细写进模板 20-25 六行（单行块），AMOUNT/小计/总额是公式，覆盖缓存值让预览也正确；
#   · 每行产品图嵌进 PICTURE 列（B:C）。
# 说明：模板自带 6 行明细，超过 6 行的报价当前只导前 6 行（行复制二期做）。
require 'zip'

class Crm::QuoteTemplateFiller
  TEMPLATE = Rails.root.join('lib/quote/quote_template.xlsx')

  SHEET = 'xl/worksheets/sheet1.xml'.freeze
  DRAWING = 'xl/drawings/drawing1.xml'.freeze
  DRAWING_RELS = 'xl/drawings/_rels/drawing1.xml.rels'.freeze
  CONTENT_TYPES = '[Content_Types].xml'.freeze
  IMAGE_REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze

  ITEM_TOP = 20        # 明细起始行（20-25，单行一项）
  MAX_ITEMS = 6        # 模板自带 6 行
  PICTURE_COL = 1      # PICTURE 列 = B（0 基）

  EMU_PER_PX = 9525
  EMU_PER_PT = 12_700
  # PICTURE 格：B(宽16)+C(宽14) ≈ 220px 宽，行高 43.5pt。
  PIC_CELL_W = 220 * EMU_PER_PX
  PIC_CELL_H = (43.5 * EMU_PER_PT).round
  PIC_PAD = 19_050

  def initialize(quote)
    @quote = quote
  end

  def to_stream
    entries = read_template
    entries[SHEET] = entries[SHEET].force_encoding('UTF-8')
    entries[SHEET] = fill_sheet(entries[SHEET])
    embed_item_pictures(entries)
    repackage(entries)
  end

  private

  def items
    @items ||= @quote.line_items.order(:id).to_a.first(MAX_ITEMS)
  end

  def customer
    @quote.crm_customer
  end

  def fill_sheet(xml)
    data = xml[%r{<sheetData>.*?</sheetData>}m].dup

    # 表头 + 买方（写进既有空格，保留样式）。
    data = set_cell_str(data, 'C8', @quote.quote_no)
    data = set_cell_str(data, 'G8', @quote.quote_date&.strftime('%Y-%m-%d'))
    data = set_cell_str(data, 'B11', contact_name)
    data = set_cell_str(data, 'B12', customer&.name)
    data = set_cell_str(data, 'B13', customer&.trade_country)
    data = set_cell_str(data, 'B14', customer&.contact_email)
    data = set_cell_str(data, 'B15', customer&.contact_phone)
    data = set_cell_str(data, 'B16', customer&.website)
    data = set_cell_str(data, 'F11', @quote.quote_currency.presence || 'USD')

    # 明细行 20-25：有货填数据、无货清空（H 列保留公式、缓存值随之更新）。
    (0...MAX_ITEMS).each do |i|
      row = ITEM_TOP + i
      item = items[i]
      data = fill_item_row(data, row, item)
    end

    # 小计 / 运费 / 总额（公式缓存值覆盖成实算值，非重算预览也正确）。
    subtotal = items.sum { |it| it.amount_micros.to_i }
    total = @quote.total_amount_micros.to_i
    data = set_formula_cache(data, 'H26', micros_to_num(subtotal))
    data = set_cell_num(data, 'H27', micros_to_num(total - subtotal)) # 运费=总额−小计（含折扣/税净额）
    data = set_formula_cache(data, 'H28', micros_to_num(total))

    xml.sub(%r{<sheetData>.*?</sheetData>}m, data)
  end

  def fill_item_row(data, row, item)
    data = set_cell_str(data, "A#{row}", item&.name)
    data = set_cell_str(data, "D#{row}", item ? (item.spec_snapshot.presence || item.remark) : nil)
    data = set_cell_num(data, "F#{row}", item&.quantity)
    data = set_cell_num(data, "G#{row}", item ? micros_to_num(item.unit_price_micros) : nil)
    set_formula_cache(data, "H#{row}", item ? micros_to_num(item.amount_micros) : nil)
  end

  def contact_name
    @quote.contact&.name.presence || customer&.primary_contact_name
  end

  # —— 图片：每行产品图嵌进 PICTURE 列（B:C），复用模板 drawing1（原只锚 LOGO）。——
  def embed_item_pictures(entries)
    anchors = +''
    rels = +''
    exts = []
    items.each_with_index do |item, i|
      next unless item.picture.attached?

      ext = picture_ext(item)
      bytes = item.picture.download
      exts << ext
      entries["xl/media/quote_item_#{i}.#{ext}"] = bytes
      rels << %(<Relationship Id="rIdQt#{i}" Type="#{IMAGE_REL_TYPE}" Target="../media/quote_item_#{i}.#{ext}"/>)
      anchors << item_anchor(i, image_size(bytes))
    rescue StandardError => e
      Rails.logger.warn("[Crm::QuoteTemplate] item=#{item.id} picture embed failed: #{e.message}")
    end
    return if anchors.empty?

    entries[DRAWING] = entries[DRAWING].force_encoding('UTF-8').sub('</xdr:wsDr>', "#{anchors}</xdr:wsDr>")
    entries[DRAWING_RELS] = entries[DRAWING_RELS].force_encoding('UTF-8').sub('</Relationships>', "#{rels}</Relationships>")
    entries[CONTENT_TYPES] = ensure_content_types(entries[CONTENT_TYPES].force_encoding('UTF-8'), exts.uniq)
  end

  # 第 i 行明细的图片锚点：PICTURE 列（B）、行 = ITEM_TOP-1+i（0 基），等比缩放居中不变形。
  def item_anchor(i, size)
    top0 = (ITEM_TOP - 1) + i
    return fill_anchor(i, top0) unless size

    w = size[0] * EMU_PER_PX
    h = size[1] * EMU_PER_PX
    scale = [(PIC_CELL_W - (2 * PIC_PAD)).to_f / w, (PIC_CELL_H - (2 * PIC_PAD)).to_f / h].min
    scale = [scale, 1.0].min
    fw = (w * scale).round
    fh = (h * scale).round
    off_x = ((PIC_CELL_W - fw) / 2).round
    off_y = ((PIC_CELL_H - fh) / 2).round
    <<~XML.delete("\n")
      <xdr:oneCellAnchor>
      <xdr:from><xdr:col>#{PICTURE_COL}</xdr:col><xdr:colOff>#{off_x}</xdr:colOff><xdr:row>#{top0}</xdr:row><xdr:rowOff>#{off_y}</xdr:rowOff></xdr:from>
      <xdr:ext cx="#{fw}" cy="#{fh}"/>
      <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="#{1000 + i}" name="quote_item_#{i}"/>
      <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>
      <xdr:blipFill><a:blip r:embed="rIdQt#{i}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
      <xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="#{fw}" cy="#{fh}"/></a:xfrm>
      <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>
      <xdr:clientData/></xdr:oneCellAnchor>
    XML
  end

  def fill_anchor(i, top0)
    <<~XML.delete("\n")
      <xdr:twoCellAnchor editAs="oneCell">
      <xdr:from><xdr:col>#{PICTURE_COL}</xdr:col><xdr:colOff>19050</xdr:colOff><xdr:row>#{top0}</xdr:row><xdr:rowOff>19050</xdr:rowOff></xdr:from>
      <xdr:to><xdr:col>#{PICTURE_COL + 2}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>#{top0 + 1}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>
      <xdr:pic><xdr:nvPicPr><xdr:cNvPr id="#{1000 + i}" name="quote_item_#{i}"/>
      <xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>
      <xdr:blipFill><a:blip r:embed="rIdQt#{i}"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>
      <xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>
      <xdr:clientData/></xdr:twoCellAnchor>
    XML
  end

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

  # 写文本进既有单元格（inlineStr），保留原有样式 s。nil/空 → 清空该格文本。
  def set_cell_str(data, ref, value)
    data.sub(%r{<c r="#{ref}"([^>]*?)(?:/>|>.*?</c>)}m) do
      style = Regexp.last_match(1)[/s="\d+"/]
      style_attr = style ? " #{style}" : ''
      if value.to_s.empty?
        %(<c r="#{ref}"#{style_attr}/>)
      else
        %(<c r="#{ref}"#{style_attr} t="inlineStr"><is><t xml:space="preserve">#{xml_escape(value)}</t></is></c>)
      end
    end
  end

  # 写数值进既有单元格，保留原样式 s。nil → 清空。
  def set_cell_num(data, ref, num)
    data.sub(%r{<c r="#{ref}"([^>]*?)(?:/>|>.*?</c>)}m) do
      style = Regexp.last_match(1)[/s="\d+"/]
      style_attr = style ? " #{style}" : ''
      body = num.nil? ? '' : "<v>#{num}</v>"
      %(<c r="#{ref}"#{style_attr}>#{body}</c>)
    end
  end

  # 覆盖公式单元格的缓存值 <v>（保留 <f> 公式）。nil → 清成空缓存。
  def set_formula_cache(data, ref, value)
    data.sub(%r{(<c r="#{ref}"[^>]*><f[^>]*>.*?</f>)(?:<v>.*?</v>)?</c>}m) do
      cache = value.nil? ? '' : "<v>#{value}</v>"
      "#{Regexp.last_match(1)}#{cache}</c>"
    end
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

  def micros_to_num(micros)
    return nil if micros.nil?

    f = micros / 1_000_000.0
    (f % 1).zero? ? f.to_i : f
  end

  def xml_escape(value)
    value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '&#10;')
  end
end
