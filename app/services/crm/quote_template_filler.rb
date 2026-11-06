# 把报价数据填进公司原始模板（lib/quote/quote_template.xlsx 的 Quotation 表），保住 logo/字体/线条/合并 —— 真·1:1。
# 用 ZIP + 字符串改 XML（rubyzip 现成），不重画、不加依赖：
#   · 表头/买方值写进模板既有空格（inlineStr，保留原样式）；
#   · 明细写进模板 20-25 六行（单行块），AMOUNT/小计/总额是公式，覆盖缓存值让预览也正确；
#   · 每行产品图嵌进 PICTURE 列（B:C）。
# 说明：模板自带 6 行明细，超过 6 行的报价当前只导前 6 行（行复制二期做）。
require 'zip'
require 'cgi'

class Crm::QuoteTemplateFiller
  TEMPLATE = Rails.root.join('lib/quote/quote_template.xlsx')

  SHEET = 'xl/worksheets/sheet1.xml'.freeze
  DRAWING = 'xl/drawings/drawing1.xml'.freeze
  DRAWING_RELS = 'xl/drawings/_rels/drawing1.xml.rels'.freeze
  CONTENT_TYPES = '[Content_Types].xml'.freeze
  IMAGE_REL_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze

  ITEM_TOP = 20        # 明细起始行（20-25，单行一项）
  MAX_ITEMS = 6        # 模板自带 6 行
  # 卖方抬头静态网址（与 PI 一致；联系人/手机/邮箱走业务员「我的卖方信息」预录）。
  SELLER_WEB = 'www.wintouchcn.com   |   https://wintouchtech.com'.freeze
  PICTURE_COL = 1      # PICTURE 列 = B（0 基）

  EMU_PER_PX = 9525
  EMU_PER_PT = 12_700
  # PICTURE 格：B(宽16)+C(宽14) ≈ 220px 宽，行高 43.5pt。
  PIC_CELL_W = 220 * EMU_PER_PX
  PIC_CELL_H = (43.5 * EMU_PER_PT).round
  PIC_PAD = 19_050

  # 模板里固定不变的那部分（公司抬头/地址、右侧条款默认值、条款正文、页脚）直接从 xlsx 里读，
  # 在线预览照着渲染。这样换了模板文件预览自动跟着变，不用在 Ruby 里再抄一份文案。
  def self.static_text
    @static_text ||= begin
      entries = {}
      Zip::File.open(TEMPLATE) { |zip| zip.each { |e| entries[e.name] = e.get_input_stream.read } }
      strings = entries['xl/sharedStrings.xml'].force_encoding('UTF-8')
                                               .scan(%r{<si>(.*?)</si>}m)
                                               .map { |m| CGI.unescapeHTML(m[0].gsub(%r{<[^>]+>}, '')) }
      sheet = entries[SHEET].force_encoding('UTF-8')
      cell = lambda do |ref|
        idx = sheet[%r{<c r="#{ref}"[^>]*t="s"[^>]*><v>(\d+)</v>}, 1]
        idx && strings[idx.to_i]
      end
      {
        company_name: cell.call('D1'),
        company_address: cell.call('D4'),
        seller_contact: cell.call('D2'),
        seller_email: cell.call('D3'),
        title: cell.call('A6'),
        no_label: cell.call('A8'),
        date_label: cell.call('E8'),
        left_band: cell.call('A10'),
        right_band: cell.call('E10'),
        # 左栏标签 Attention/Company/Country/Email/Tel./Website
        left_labels: (11..16).map { |r| cell.call("A#{r}") },
        # 右栏标签与默认值：币种那格由导出时写入，其余（贸易条款/装运港/交期/付款/有效期）是模板固定值
        right_labels: (11..16).map { |r| cell.call("E#{r}") },
        right_defaults: (11..16).map { |r| cell.call("F#{r}") },
        detail_band: cell.call('A18'),
        columns: %w[A B D F G H].map { |c| cell.call("#{c}19") },
        subtotal_label: cell.call('A26'),
        freight_label: cell.call('A27'),
        total_label: cell.call('A28'),
        terms_band: cell.call('A30'),
        terms: (31..37).map { |r| cell.call("A#{r}") }.compact,
        footer: cell.call('A40')
      }
    end
  end

  # 落款署名（与导出同口径），给在线预览用。
  def self.issuer_name_for(quote)
    new(quote).send(:issuer_name)
  end

  # 买方联系人（与导出同口径）。
  def self.contact_name_for(quote)
    new(quote).send(:contact_name)
  end

  # 卖方「我的卖方信息」两行（没预录则回落模板默认），与导出同口径。
  def self.seller_lines_for(quote)
    seller_lines_for_owner(quote.account_id, quote.owner_id || quote.handled_by_id)
  end

  # 下面两个按业务员取，不经过单据——新建时单据还没落库，右侧实时预览照样要这几行。
  def self.seller_lines_for_owner(account_id, owner_id)
    sp = profile_for(account_id, owner_id)
    return [static_text[:seller_contact], static_text[:seller_email]] unless sp

    ["Contact: #{sp.contact_name}   |   Mobile: #{sp.mobile}",
     "Email: #{sp.email}   |   #{SELLER_WEB}"]
  end

  def self.issuer_name_for_owner(account_id, owner_id)
    sp = profile_for(account_id, owner_id)
    return sp.contact_name if sp

    user = User.find_by(id: owner_id)
    (user&.crm_name.presence || user&.name).to_s
  end

  def self.profile_for(account_id, owner_id)
    owner_id && Crm::PiSellerProfile.find_by(account_id: account_id, owner_id: owner_id)
  end

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

  MAX_TOTAL_ITEMS = 50 # 上限兜底，避免超大报价把导出撑爆

  def items
    @items ||= @quote.line_items.order(:id).to_a.first(MAX_TOTAL_ITEMS)
  end

  def customer
    @quote.crm_customer
  end

  def fill_sheet(xml)
    data = xml[%r{<sheetData[^>]*>.*?</sheetData>}m].dup

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

    # 卖方落款（联系人/手机/邮箱）：按报价单业务员的「我的卖方信息」预录填，未录则保留模板默认。
    if (sp = seller_profile)
      data = set_cell_str(data, 'D2', "Contact: #{sp.contact_name}   |   Mobile: #{sp.mobile}")
      data = set_cell_str(data, 'D3', "Email: #{sp.email}   |   #{SELLER_WEB}")
    end

    # 明细：模板自带 6 行；明细多于 6 行时克隆明细行、把下方（小计/运费/总额/条款/落款）整体下移 delta。
    n = items.size
    rows_needed = [n, MAX_ITEMS].max
    delta = rows_needed - MAX_ITEMS
    data = rebuild_item_area(data, rows_needed, delta)

    # 小计 / 运费 / 总额（写到下移后的行号）。
    subtotal = items.sum { |it| it.amount_micros.to_i }
    total = @quote.total_amount_micros.to_i
    last_item_row = ITEM_TOP + rows_needed - 1
    data = set_subtotal_cell(data, 26 + delta, subtotal, last_item_row)
    data = set_cell_num(data, "H#{27 + delta}", micros_to_num(total - subtotal)) # 运费=总额−小计（含折扣/税净额）
    # 总额格是加粗大字，纯数字在窄列会显示成 ####；改写成「币种 金额」文本，靠右溢出显示不再 ####。
    data = set_cell_str(data, "H#{28 + delta}", format_money(total))
    # 落款「ISSUED BY / 姓名」随报价单业务员走（外发文档优先英文名），不再写死模板里的名字。
    data = set_cell_str(data, "A#{38 + delta}", "ISSUED BY\n#{issuer_name}")

    xml = xml.sub(%r{<sheetData[^>]*>.*?</sheetData>}m, data)
    rebuild_merges(xml, rows_needed, delta)
  end

  # 报价单业务员的「我的卖方信息」预录（复用 PI 的同一份，按 owner→经办人 取）。
  def seller_profile
    return @seller_profile if defined?(@seller_profile)

    uid = @quote.owner_id || @quote.handled_by_id
    @seller_profile = uid && Crm::PiSellerProfile.find_by(account_id: @quote.account_id, owner_id: uid)
  end

  # 报价单落款署名：优先「我的卖方信息」联系人；否则业务员英文名（兜底真名）。
  def issuer_name
    return seller_profile.contact_name if seller_profile

    user = User.find_by(id: @quote.owner_id || @quote.handled_by_id)
    (user&.crm_name.presence || user&.name).to_s
  end

  # 「币种 千分位金额」文本，如 "USD 54,516.00"。
  def format_money(micros)
    return '' if micros.nil?

    cur = @quote.quote_currency.presence || 'USD'
    "#{cur} #{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', micros / 1_000_000.0))}"
  end

  # 把明细区重建成 rows_needed 行：保留行首(<20)、按模板克隆明细行(20..19+rows_needed)、
  # 下方行(>=26)整体下移 delta。以行元素数组处理，避免整串正则误伤。
  def rebuild_item_area(data, rows_needed, delta)
    open_tag = data[/<sheetData[^>]*>/]
    inner = data[/<sheetData[^>]*>(.*)<\/sheetData>/m, 1]

    head = []
    tail = []
    template = nil
    last_orig_item = ITEM_TOP + MAX_ITEMS - 1
    inner.scan(/<row r="(\d+)"[^>]*?(?:\/>|>.*?<\/row>)/m) do
      num = Regexp.last_match(1).to_i
      rxml = Regexp.last_match(0)
      if num < ITEM_TOP
        head << rxml
      elsif num <= last_orig_item
        template = rxml if num == ITEM_TOP # 原始明细行(20-25)丢弃，用模板行 20 重建
      else
        tail << renumber_row(rxml, num, num + delta)
      end
    end

    new_items = (0...rows_needed).map { |i| build_item_row(template, ITEM_TOP + i, items[i]) }
    "#{open_tag}#{(head + new_items + tail).join}</sheetData>"
  end

  # 用模板行(row 20)克隆出第 rownum 行并填入 item（无 item 则留空行，保留边框/样式）。
  def build_item_row(template, rownum, item)
    r = renumber_row(template, ITEM_TOP, rownum)
    r = set_cell_str(r, "A#{rownum}", item&.name)
    r = set_cell_str(r, "D#{rownum}", item ? (item.spec_snapshot.presence || item.remark) : nil)
    r = set_cell_num(r, "F#{rownum}", item&.quantity)
    r = set_cell_num(r, "G#{rownum}", item ? micros_to_num(item.unit_price_micros) : nil)
    set_amount_cell(r, rownum, item)
  end

  # 行金额格：保留 IF 公式（引用本行 F/G）+ 覆盖缓存值。
  def set_amount_cell(row_xml, rownum, item)
    cache = item ? "<v>#{micros_to_num(item.amount_micros)}</v>" : ''
    row_xml.sub(/<c r="H#{rownum}"([^>]*?)(?:\/>|>.*?<\/c>)/m) do
      style = Regexp.last_match(1)[/s="\d+"/] || 's="15"'
      %(<c r="H#{rownum}" #{style} t="n"><f aca="false">IF(F#{rownum}="","",F#{rownum}*G#{rownum})</f>#{cache}</c>)
    end
  end

  # 小计格：改写公式为覆盖全部明细行的 SUM + 覆盖缓存值。
  def set_subtotal_cell(data, row, subtotal_micros, last_item_row)
    data.sub(/<c r="H#{row}"([^>]*?)(?:\/>|>.*?<\/c>)/m) do
      style = Regexp.last_match(1)[/s="\d+"/] || 's="20"'
      %(<c r="H#{row}" #{style} t="n"><f aca="false">SUM(H#{ITEM_TOP}:H#{last_item_row})</f><v>#{micros_to_num(subtotal_micros)}</v></c>)
    end
  end

  # 行号平移：只改 <row r=> 与 <c r=> 的行号，不动公式体（相关公式格另行整格重写）。
  def renumber_row(row_xml, oldnum, newnum)
    row_xml.sub(/<row r="#{oldnum}"/, %(<row r="#{newnum}"))
           .gsub(/<c r="([A-Z]+)#{oldnum}"/) { %(<c r="#{Regexp.last_match(1)}#{newnum}") }
  end

  # 重建合并单元格：行首(<20)保留；明细行合并按 rows_needed 重新生成；下方(>=26)整体下移 delta。
  def rebuild_merges(xml, rows_needed, delta)
    block = xml[/<mergeCells count="\d+">.*?<\/mergeCells>/m]
    return xml if block.nil?

    last_orig_item = ITEM_TOP + MAX_ITEMS - 1
    out = []
    block.scan(/<mergeCell ref="([A-Z]+)(\d+):([A-Z]+)(\d+)"\/>/) do
      c1, r1, c2, r2 = Regexp.last_match(1), Regexp.last_match(2).to_i, Regexp.last_match(3), Regexp.last_match(4).to_i
      next if r1 >= ITEM_TOP && r1 <= last_orig_item # 原明细行合并丢弃，下面按需重建

      if r1 >= ITEM_TOP + MAX_ITEMS
        out << "#{c1}#{r1 + delta}:#{c2}#{r2 + delta}"
      else
        out << "#{c1}#{r1}:#{c2}#{r2}"
      end
    end
    (0...rows_needed).each do |i|
      r = ITEM_TOP + i
      out << "B#{r}:C#{r}"
      out << "D#{r}:E#{r}"
    end
    cells = out.map { |ref| %(<mergeCell ref="#{ref}"/>) }.join
    xml.sub(/<mergeCells count="\d+">.*?<\/mergeCells>/m, %(<mergeCells count="#{out.size}">#{cells}</mergeCells>))
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
