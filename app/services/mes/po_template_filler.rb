# 把「按供应商拆分」的采购单数据填进公司原始 .xlsx 模板（lib/purchase_order/），保住 logo/公章/字体/线条/合并 —— 真·1:1。
# 照 Crm::PiTemplateFiller 那套：ZIP + 字符串改 XML（rubyzip 现成），不重画、不加依赖：
#   · 表头字段（供应商/PO号/日期/地址/币别）改 sharedStrings；
#   · 明细按项数克隆模板里的「明细行」，下方各行（合计/条款/公章锚点）整体下移；
#   · 合计行的数量/金额缓存值按实算覆盖。
# 抬头/税口径按 bill_entity 选模板（默认取供应商档案，导出时可手动覆盖）：
#   liontek → 联迪含税合同；其它/nil → 深圳联合触控未税订单。
require 'zip'
require 'nokogiri'

class Mes::PoTemplateFiller # rubocop:disable Metrics/ClassLength
  SHEET = 'xl/worksheets/sheet1.xml'.freeze
  STRINGS = 'xl/sharedStrings.xml'.freeze
  DRAWING = 'xl/drawings/drawing1.xml'.freeze

  # 每个开票主体一套模板配置：模板路径 + 各表头字段目标 sharedString 索引 + 明细/合计行结构。
  # taxed=true 用含税单价(taxed_rate_micros)，false 用未税单价(untaxed_rate_micros)。
  TEMPLATES = {
    'wintouch' => {
      file: 'lib/purchase_order/po_template_wintouch.xlsx',
      taxed: false,
      currency: '不含税 RMB',
      # 表头富文本串（模板样例值）→ 填入模板：供应商块 / PO号 / 日期 / 地址 / 币别在同一格。
      supplier_si: 4,  # "供应商 ：...\n联系人 ：..."
      po_no_si: 5,     # "采购订单号 ：PO..."
      date_si: 6,      # "采购日期：..."
      address_si: 7,   # "地址：...\n一、产品名称..."（地址在首段，尾段是固定说明，保留）
      currency_si: 9,  # "币别：含税  RMB"
      supplier_prefix: '供应商 ：   ',
      contact_prefix: '联系人 ：   ',
      po_no_prefix: '采购订单号 ：',
      date_prefix: '采购日期：',
      address_prefix: '地址：  ',
      address_tail_si: 7, # 地址串尾部保留的固定说明（换行后整段）
      currency_prefix: '币别：',
      first_item_row: 9,   # 明细样例首行
      # 模板第 10 行其实是**合计行**（E10=合计、I10=总数量、L10=总金额），不是第二行样例明细。
      # 原来按 2 行样例算，tail 从第 11 行起，合计行正好落在被明细覆盖的区间里被吃掉——
      # 一个供应商下好几颗料时整张单没有合计（采购反馈点名的问题）。
      sample_item_rows: 1,
      total_row: 10,         # 合计行：E=合计、I=总数量、L=总金额
      total_qty_ref: 'I',
      total_amount_ref: 'L',
      # 明细单行各列（值列 + 样式），克隆行时套用；文本列用 inlineStr。
      cell_layout: {
        seq: { col: 'A', s: '14', type: :num },
        code: { col: 'B', s: '10', type: :str },
        name: { col: 'C', s: '10', type: :str },
        spec: { col: 'E', s: '13', type: :str },
        unit: { col: 'G', s: '10', type: :str },
        qty: { col: 'I', s: '14', type: :num },
        price: { col: 'J', s: '14', type: :num },
        amount: { col: 'L', s: '16', type: :num },
        remark: { col: 'M', s: '10', type: :str }
      },
      # 明细行内需保留合并的列区间（相对每行）：名称 C:D、规格 E:F、单位 G:H、单价 J:K。
      row_merges: [%w[C D], %w[E F], %w[G H], %w[J K]]
    },
    'liontek' => {
      file: 'lib/purchase_order/po_template_liontek.xlsx',
      taxed: true,
      currency: '含税 RMB',
      supplier_si: 5,
      po_no_si: 6,
      date_si: 7,
      address_si: 8,
      currency_si: 8, # 联迪地址与币别在同一格（address_si == currency_si），一起重写
      supplier_prefix: '供应商 ：   ',
      contact_prefix: '联系人 ：  ',
      po_no_prefix: '采购合同号 ：     ',
      date_prefix: '采购日期：   ',
      address_prefix: '地址：  ',
      currency_prefix: '币别：含税   RMB',
      first_item_row: 8,
      sample_item_rows: 1,
      total_row: 9,          # 合计行：B=合计：、H=总数量、J=总金额
      total_qty_ref: 'H',
      total_amount_ref: 'J',
      cell_layout: {
        seq: { col: 'A', s: nil, type: :num },
        code: { col: 'B', s: '?', type: :str },
        name: { col: 'C', s: '?', type: :str },
        spec: { col: 'D', s: '?', type: :str },
        unit: { col: 'F', s: '?', type: :str },
        qty: { col: 'H', s: nil, type: :num },
        price: { col: 'I', s: nil, type: :num },
        amount: { col: 'J', s: nil, type: :num },
        remark: { col: 'M', s: '?', type: :str }
      },
      row_merges: [%w[D E], %w[F G], %w[J L]]
    }
  }.freeze

  # supplier: Mes::Supplier（可 nil）；items: 该供应商的 purchase_items 数组；purchase_order: Mes::PurchaseOrder。
  # bill_entity: 手动指定抬头（导出时临时改，不动供应商档案）；不传就按档案走。
  def initialize(supplier:, items:, purchase_order:, bill_entity: nil)
    @supplier = supplier
    @items = items
    @po = purchase_order
    @cfg = TEMPLATES[bill_entity.presence || supplier&.bill_entity] || TEMPLATES['wintouch']
  end

  # 返回该供应商 .xlsx 的二进制流（IO）。
  def to_stream
    entries = read_template
    entries[STRINGS] = entries[STRINGS].force_encoding('UTF-8')
    entries[SHEET] = entries[SHEET].force_encoding('UTF-8')
    entries[STRINGS] = fill_strings(entries[STRINGS])
    filled_strings = extract_strings(entries[STRINGS])
    entries[SHEET] = fill_sheet(entries[SHEET])
    entries[SHEET] = grow_row_heights(entries[SHEET], filled_strings)
    entries[SHEET] = widen_money_columns(entries[SHEET])
    format_money_cells(entries)
    shift_drawing(entries) if entries[DRAWING]
    repackage(entries)
  end

  private

  def template_path
    Rails.root.join(@cfg[:file])
  end

  # 表头字段填进 sharedStrings：把样例串按前缀重建为本单值（供应商/PO号/日期/地址/币别）。
  # 地址串尾部若含固定说明段（wintouch 的「一、产品名称...」），保留不动。
  def fill_strings(xml)
    map = header_string_map
    idx = -1
    xml.gsub(%r{<si>.*?</si>}m) do |si|
      idx += 1
      if map.key?(idx)
        "<si>#{t_node(map[idx])}</si>"
      elsif si.include?('交货时间、地点')
        date = @po.delivery_date&.strftime('%Y年%-m月%-d日') || '待确认'
        si.gsub(/\d{4}年\d{1,2}月\d{1,2}日/, date)
      else
        si
      end
    end
  end

  # 表头各字段 → 目标 sharedString 索引的映射（供应商/PO号/日期/地址/币别）。
  def header_string_map
    map = {
      @cfg[:supplier_si] => "#{@cfg[:supplier_prefix]}#{supplier_name}\n#{@cfg[:contact_prefix]}#{@supplier&.contact_name}",
      # 发给供应商的是**他这一家**的单号（PU-20260928-04-01），不是整张单的 po_no——
      # 他交货写这个号、仓库按这个号入库、财务按这个号对账（见 Mes::PoSupplierNumber）。
      @cfg[:po_no_si] => "#{@cfg[:po_no_prefix]}#{Mes::PoSupplierNumber.for(@po, @supplier&.id)}",
      @cfg[:date_si] => "#{@cfg[:date_prefix]}#{po_date}",
      @cfg[:address_si] => address_value
    }
    map[@cfg[:currency_si]] = currency_value if @cfg[:currency_si] != @cfg[:address_si]
    map
  end

  # 地址串：liontek 地址与币别共格（一起重写）；wintouch 地址后保留固定说明尾段。
  def address_value
    if @cfg[:currency_si] == @cfg[:address_si]
      "#{@cfg[:address_prefix]}#{@supplier&.address}\n\n#{@cfg[:currency_prefix]}"
    else
      tail = address_tail
      base = "#{@cfg[:address_prefix]}#{@supplier&.address}"
      tail.present? ? "#{base}\n\n#{tail}" : base
    end
  end

  # wintouch 地址格尾部固定说明（原样例「\n\n一、产品名称...」），保留其换行后的整段。
  def address_tail
    return '' unless @cfg[:address_tail_si]

    raw = @template_strings[@cfg[:address_tail_si]].to_s
    parts = raw.split("\n").map(&:strip).reject(&:empty?)
    parts.length > 1 ? parts[1..].join("\n") : ''
  end

  def currency_value
    "#{@cfg[:currency_prefix]}#{@cfg[:currency]}"
  end

  def supplier_name
    @supplier&.name.presence || '未指定供应商'
  end

  def po_date
    @po.created_at&.to_date&.to_s
  end

  # 明细区：按项数克隆首行样式，尾部（合计/条款/公章锚点）整体下移 delta 行。
  def fill_sheet(xml)
    top = @cfg[:first_item_row]
    n = [@items.length, 1].max
    @delta = n - @cfg[:sample_item_rows] # 明细行数变化量（正=下移，负=上移）
    @tail_start = top + @cfg[:sample_item_rows]

    data = xml[%r{<sheetData>.*?</sheetData>}m]
    row_nums = data.scan(/<row r="(\d+)"/).flatten.map(&:to_i)

    head = rows_between(data, row_nums.min, top - 1)
    tail = shifted_tail(data, row_nums.max)

    new_data = "<sheetData>#{head}#{item_region(top)}#{tail}</sheetData>"
    new_data = fill_total(new_data, @delta) if @cfg[:total_row]

    xml = xml.sub(%r{<sheetData>.*?</sheetData>}m, new_data)
    rebuild_merges(xml, n, @delta)
  end

  # 尾部（合计/条款/公章说明）区段：明细区之后所有行，按 delta 整体位移。
  def shifted_tail(data, max_row)
    tail = rows_between(data, @tail_start, max_row)
    @delta.zero? ? tail : shift_rows(tail, @delta)
  end

  # 明细区 XML：每项一行（无明细则一空行）。
  def item_region(top)
    return single_empty_row(top) if @items.empty?

    @items.each_with_index.map { |it, i| item_row(it, top + i, i + 1) }.join
  end

  # 单条明细行：套模板首行样式，值列填数据（文本 inlineStr，数值 <v>）。
  def item_row(item, row, seq)
    layout = @cfg[:cell_layout]
    vals = {
      seq: seq,
      code: code(item),
      name: name(item),
      spec: spec(item),
      unit: item.unit,
      qty: fmt_num(item.qty),
      price: fmt_num(unit_price(item)),
      amount: fmt_num(amount(item)),
      remark: remark(item)
    }
    cells = base_row_cells(row)
    layout.each do |field, meta|
      cells[meta[:col]] = cell_xml(meta[:col], row, style_for(meta), meta[:type], vals[field])
    end
    "<row r=\"#{row}\" spans=\"1:13\"#{row_ht_attr}>#{cells.values.join}</row>"
  end

  # 空单占位行（无明细时保留一行结构）。
  def single_empty_row(row)
    cells = base_row_cells(row)
    "<row r=\"#{row}\" spans=\"1:13\"#{row_ht_attr}>#{cells.values.join}</row>"
  end

  # 生成的明细行沿用模板样例明细行的行高（否则会变默认矮行、文字挤在一起）。
  def row_ht_attr
    @item_row_ht ? %( ht="#{@item_row_ht}" customHeight="1") : ''
  end

  # 按模板首行的真实单元格样式，构造 A..M 全列基础格（保样式、无值），供覆盖值列。
  def base_row_cells(row)
    @first_row_styles.each_with_object({}) do |(col, s), h|
      h[col] = s ? "<c r=\"#{col}#{row}\" s=\"#{s}\"/>" : "<c r=\"#{col}#{row}\"/>"
    end
  end

  # 取模板首行各列样式（s 值），'?' 占位的 layout 用它回填。
  def style_for(meta)
    return meta[:s] unless meta[:s].nil? || meta[:s] == '?'

    @first_row_styles[meta[:col]]
  end

  def cell_xml(col, row, style, type, value)
    s_attr = style ? " s=\"#{style}\"" : ''
    if type == :str
      "<c r=\"#{col}#{row}\"#{s_attr} t=\"inlineStr\"><is>#{t_node(value)}</is></c>"
    else
      v = value.nil? ? '' : "<v>#{value}</v>"
      "<c r=\"#{col}#{row}\"#{s_attr}>#{v}</c>"
    end
  end

  # 合计行：把总数量/总金额缓存值按实算覆盖（沿用模板样式与「合计：」标签）。
  def fill_total(data, delta)
    row = @cfg[:total_row] + delta
    data = set_cell_num(data, "#{@cfg[:total_qty_ref]}#{row}", total_qty)
    set_cell_num(data, "#{@cfg[:total_amount_ref]}#{row}", total_amount)
  end

  def set_cell_num(data, ref, value)
    data.sub(%r{(<c r="#{ref}"[^>]*?)(?:/>|>.*?</c>)}m) do
      "#{Regexp.last_match(1).sub(/\st="[^"]*"/, '')}><v>#{fmt_num(value)}</v></c>"
    end
  end

  # 抽取 [from,to] 行的原始 XML。
  def rows_between(data, from, to)
    (from..to).map { |r| data[%r{<row r="#{r}"[^>]*>.*?</row>}m].to_s }.join
  end

  # 行号/单元格引用/公式引用整体 +delta（tail 段起点在明细之后）。
  def shift_rows(xml, delta)
    shifted = xml.gsub(/r="([A-Z]*)(\d+)"/) { %(r="#{Regexp.last_match(1)}#{Regexp.last_match(2).to_i + delta}") }
    shifted.gsub(%r{<f>(.*?)</f>}m) do
      inner = Regexp.last_match(1).gsub(/([A-Z]+)(\d+)/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).to_i + delta}" }
      "<f>#{inner}</f>"
    end
  end

  # 重建 mergeCells：表头（明细区之上）保留；明细区之下的 +delta；明细行内合并按项数重建。
  def rebuild_merges(xml, item_count, delta)
    block = xml[%r{<mergeCells[^>]*>(.*?)</mergeCells>}m, 1]
    return xml unless block

    kept = block.scan(/ref="([^"]+)"/).flatten.filter_map { |ref| keep_merge(ref, delta) }
    kept.concat(item_row_merges(item_count))
    new_block = %(<mergeCells count="#{kept.length}">#{kept.map { |r| %(<mergeCell ref="#{r}"/>) }.join}</mergeCells>)
    xml.sub(%r{<mergeCells[^>]*>.*?</mergeCells>}m, new_block)
  end

  # 单个模板合并区间的去留：明细区之上保留原样，之下 +delta，明细样例区间丢弃（改由行内重建）。
  def keep_merge(ref, delta)
    top = @cfg[:first_item_row]
    sample_bottom = top + @cfg[:sample_item_rows] - 1
    r1, r2 = ref.scan(/\d+/).map(&:to_i)
    return ref if r2 < top
    return shift_ref(ref, delta) if r1 > sample_bottom

    nil
  end

  # 按项数重建的明细行内合并（名称/规格/单位/金额等跨列）。
  def item_row_merges(item_count)
    top = @cfg[:first_item_row]
    [item_count, 1].max.times.flat_map do |i|
      @cfg[:row_merges].map { |c1, c2| "#{c1}#{top + i}:#{c2}#{top + i}" }
    end
  end

  def shift_ref(ref, delta)
    ref.gsub(/([A-Z]+)(\d+)/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).to_i + delta}" }
  end

  # 公章/logo drawing 用行锚点定位；明细行数变化后，锚在明细区之下的锚点行号 +delta，
  # 保住公章跟着签字栏一起下移不错位（图片在 media/ 已随模板打包，只改锚点行号）。
  # 明细区之上的 logo（row 0）不动。锚点行号 0 基，故与 tail_start（1 基）比较用 tail_start-1。
  def shift_drawing(entries)
    return if @delta.to_i.zero?

    xml = entries[DRAWING].force_encoding('UTF-8')
    entries[DRAWING] = xml.gsub(%r{<xdr:row>(\d+)</xdr:row>}) do
      r = Regexp.last_match(1).to_i
      "<xdr:row>#{r >= @tail_start - 1 ? r + @delta : r}</xdr:row>"
    end
  end

  def read_template
    entries = {}
    Zip::File.open(template_path) do |zip|
      zip.each do |e|
        next if e.directory?

        entries[e.name] = e.get_input_stream.read
      end
    end
    @template_strings = extract_strings(entries[STRINGS].dup.force_encoding('UTF-8'))
    sheet = entries[SHEET].dup.force_encoding('UTF-8')
    @first_row_styles = extract_row_styles(sheet, @cfg[:first_item_row])
    @item_row_ht = sheet[/<row r="#{@cfg[:first_item_row]}"[^>]*\bht="([\d.]+)"/, 1]
    entries
  end

  # 解析 sharedStrings 各 <si> 文本（&#10; 还原成换行，便于取地址尾段）。
  def extract_strings(xml)
    xml.scan(%r{<si>.*?</si>}m).map do |si|
      si.scan(%r{<t[^>]*>(.*?)</t>}m).flatten.join.gsub('&#10;', "\n")
    end
  end

  # 取某行各列的样式属性 s（用于克隆明细行、构造合计行基础格）。
  def extract_row_styles(xml, row)
    r = xml[%r{<row r="#{row}"[^>]*>.*?</row>}m].to_s
    styles = {}
    r.scan(%r{<c r="([A-Z]+)\d+"([^>]*?)(?:/>|>)}) do |col, attrs|
      s = attrs[/s="(\d+)"/, 1]
      styles[col] = s
    end
    styles
  end

  # 按文本行数自动撑高：模板里部分多行条款/落款行的存高偏矮又锁死了 customHeight，会截字。
  # 明细区及以下每行，若存高 < 行数×每行高，则撑到够高（只增不减）；表头合并区不动。
  LINE_PT = 16.0

  def grow_row_heights(xml, strings)
    column_widths(xml)
    xml.gsub(%r{<row [^>]*>.*?</row>}m) do |row|
      rn = row[/<row r="(\d+)"/, 1].to_i
      next row if rn < @cfg[:first_item_row]

      lines = max_cell_lines(row, strings)
      next row if lines <= 1

      needed = (lines * LINE_PT).round(1)
      current = row[/<row [^>]*\bht="([\d.]+)"/, 1].to_f
      current >= needed ? row : set_row_ht(row, needed)
    end
  end

  # 行内各格所需的最大行数。逐格解析（要知道在哪一列才能按列宽估折行）：
  # inlineStr 直接取文本，共享串按索引查填充后的 strings。
  def max_cell_lines(row, strings)
    counts = [1]
    row.scan(%r{<c\b[^>]*\br="([A-Z]+)\d+"[^>]*?(?:/>|>(.*?)</c>)}m) do |col, body|
      text = if body.to_s.include?('<is>')
               body[%r{<is>(.*?)</is>}m, 1].to_s.scan(%r{<t[^>]*>(.*?)</t>}m).flatten.join
             elsif body.to_s =~ /<v>(\d+)</ && row[/<c\b[^>]*\br="#{col}\d+"[^>]*t="s"/]
               strings[Regexp.last_match(1).to_i].to_s
             end
      counts << cell_lines(col, text) if text.present?
    end
    counts.max
  end

  # 单元格文本要占几行：先按显式换行分段，每段再按列宽估算 Excel 的自动折行。
  # 规格这类长文本模板里开了自动换行，只按 \n 算行高的话，折下去的部分会被裁掉。
  def cell_lines(col, text)
    usable = usable_width(col)
    text.gsub('&#10;', "\n").split("\n", -1).sum do |seg|
      usable.positive? ? [((display_width(seg) / usable.to_f).ceil), 1].max : 1
    end
  end

  # 可用字符宽度：本列宽 + 行内合并过去的列宽（规格 E:F 这种），留 1 格余量给内边距。
  def usable_width(col)
    cols = [col] + Array(@cfg[:row_merges]).find { |pair| pair.first == col }.to_a.drop(1)
    total = cols.sum { |c| @column_widths[col_index(c)].to_f }
    total.positive? ? total - 1 : 0
  end

  # 显示宽度：中文/全角按 2 个字符位算，其余按 1（Excel 列宽就是以字符位为单位）。
  def display_width(text)
    CGI.unescapeHTML(text).each_char.sum { |ch| ch.bytesize > 2 ? 2 : 1 }
  end

  # <cols> 里的列宽表（列号 → 宽度）。没声明的列 Excel 用默认宽，这里按 8.43 兜底。
  def column_widths(xml)
    @column_widths = Hash.new(8.43)
    xml.scan(/<col\b[^>]*\bmin="(\d+)"[^>]*\bmax="(\d+)"[^>]*\bwidth="([\d.]+)"/) do |mn, mx, w|
      (mn.to_i..mx.to_i).each { |c| @column_widths[c] = w.to_f }
    end
    @column_widths
  end

  # 金额/单价列按实际位数加宽：模板列宽是按几千块、整数单价的单子定的，
  # 金额上十万、或单价带小数位（未税价 = 含税价 ÷ 1.13，小数一串），格子里就只剩一串 #。
  # 加宽多少就从备注列匀多少（备注多半是空的），总宽不变，A4 不会被撑到第二页。
  MIN_REMARK_WIDTH = 8.0
  def widen_money_columns(xml)
    xml = widen_column(xml, :amount, amount_column_need)
    widen_column(xml, :price, price_column_need)
  end

  def widen_column(xml, key, need)
    col = @cfg.dig(:cell_layout, key, :col)
    return xml if col.blank? || need.blank?

    widths = column_widths(xml)
    idx = col_index(col)
    # 单价是跟右边一列合并着显示的（J:K），撑这格的是合并后的总宽，按总宽比才知道差多少。
    delta = (need - (usable_width(col) + 1)).round(2)
    return xml if delta <= 0

    remark_idx = col_index(@cfg.dig(:cell_layout, :remark, :col).to_s)
    spare = [widths[remark_idx] - MIN_REMARK_WIDTH, 0].max
    borrowed = [delta, spare].min
    xml = set_col_width(xml, idx, widths[idx] + delta)
    borrowed.positive? ? set_col_width(xml, remark_idx, widths[remark_idx] - borrowed) : xml
  end

  # 最宽一笔金额要几个字符位（含千分位与两位小数），再留 1 位余量。
  def amount_column_need
    widest = @items.map { |i| fmt_num(amount(i)).to_d.round(2) }.max
    return if widest.blank?

    # 单元格里是「1,250,900.00」这个样子，按两位小数 + 千分位量长度，别按原始数值量。
    ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', widest), delimiter: ',').length + 1.0
  end

  # 最长一笔单价要几个字符位：单价走 0.00#### 格式（两位起、最多六位），再留 1 位余量。
  def price_column_need
    longest = @items.map { |i| price_display_text(unit_price(i)) }.max_by(&:length)
    return if longest.blank?

    longest.length + 1.0
  end

  # 单价在格子里的样子（与 add_price_format 的 0.00#### 一致）：至少两位小数，多余的 0 不显示。
  def price_display_text(value)
    format('%.6f', value.to_d).sub(/(?<=\.\d\d)0+\z/, '')
  end

  def set_col_width(xml, idx, width)
    pattern = %r{<col\b(?=[^>]*\bmin="#{idx}")(?=[^>]*\bmax="#{idx}")[^>]*/>}
    return xml unless xml.match?(pattern)

    xml.sub(pattern) { |tag| tag.sub(/\bwidth="[\d.]+"/, %(width="#{width.round(6)}")) }
  end

  def col_index(letters)
    letters.each_char.reduce(0) { |acc, ch| acc * 26 + (ch.ord - 64) }
  end

  def text_line_count(text)
    text.gsub('&#10;', "\n").count("\n") + 1
  end

  def set_row_ht(row, height)
    open = row[/<row [^>]*>/]
    cleaned = open.gsub(/\s(?:ht|customHeight)="[^"]*"/, '')
    row.sub(/<row [^>]*>/, cleaned.sub(/\s*>\z/, %( ht="#{height}" customHeight="1">)))
  end

  # 仅替换金额单元格的数字格式，保留模板字体、边框、对齐与合并。
  # 单价保留 micros 精度，行金额和合计固定两位，避免 11.30 被显示成 11。
  XML_NS = { 's' => 'http://schemas.openxmlformats.org/spreadsheetml/2006/main' }.freeze

  def format_money_cells(entries)
    styles = Nokogiri::XML(entries.fetch('xl/styles.xml'))
    sheet = Nokogiri::XML(entries.fetch(SHEET))
    price_format_id = add_price_format(styles)
    xfs = styles.at_xpath('//s:cellXfs', XML_NS)
    cloned = {}
    money_cell_formats(price_format_id).each do |ref, format_id|
      cell = sheet.at_xpath("//s:c[@r='#{ref}']", XML_NS)
      key = [cell['s'].to_i, format_id]
      cell['s'] = cloned[key] ||= clone_number_style(xfs, *key)
    end
    entries['xl/styles.xml'] = styles.to_xml
    entries[SHEET] = sheet.to_xml
  end

  def add_price_format(styles)
    formats = styles.at_xpath('//s:numFmts', XML_NS)
    id = [163, *formats.element_children.map { |node| node['numFmtId'].to_i }].max + 1
    format = Nokogiri::XML::Node.new('numFmt', styles)
    format['numFmtId'] = id.to_s
    format['formatCode'] = '0.00####'
    formats.add_child(format)
    formats['count'] = formats.element_children.length.to_s
    id
  end

  def money_cell_formats(price_format_id)
    cells = {}
    @items.each_index do |i|
      row = @cfg[:first_item_row] + i
      cells["#{@cfg[:cell_layout][:price][:col]}#{row}"] = price_format_id
      cells["#{@cfg[:cell_layout][:amount][:col]}#{row}"] = 2
    end
    cells["#{@cfg[:total_amount_ref]}#{@cfg[:total_row] + @delta}"] = 2 if @cfg[:total_row]
    cells
  end

  def clone_number_style(xfs, original_index, format_id)
    xf = xfs.element_children[original_index].dup
    xf['numFmtId'] = format_id.to_s
    xf['applyNumberFormat'] = '1'
    index = xfs.element_children.length.to_s
    xfs.add_child(xf)
    xfs['count'] = xfs.element_children.length.to_s
    index
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

  def t_node(value)
    %(<t xml:space="preserve">#{xml_escape(value)}</t>)
  end

  # 单价：wintouch 未税 / liontek 含税；均取模型已换算好的 micros。
  def unit_price(item)
    micros = @cfg[:taxed] ? item.taxed_rate_micros : item.untaxed_rate_micros
    (micros.to_d / 1_000_000)
  end

  def amount(item)
    (item.qty.to_d * unit_price(item)).round(2)
  end

  def total_qty
    @items.sum { |it| it.qty.to_d }
  end

  def total_amount
    @items.sum { |it| amount(it) }.round(2)
  end

  # 备注列 = 产品档案备注 + 辅助属性 + 这一行自己的备注。
  # 供应商光看料号分不出要哪一种（同一个料号下有多个辅助属性），档案备注里也常写着
  # 工程对这个料的硬要求，所以这两样要跟着单子发出去。
  # **不含**生产任务单上的「采购注意事项」——那是写给我们自己采购看的，不对外。
  def remark(item)
    [item.crm_product&.remark, item.aux_attribute_name, item.remark].map { |v| v.to_s.strip }.reject(&:empty?).join(' / ')
  end

  # 料号/名称/规格：统一取产品档案(crm_product)，旧数据回落 mes_material。
  def code(item) = item.crm_product&.sku || item.mes_material&.material_no
  def name(item) = item.crm_product&.name || item.mes_material&.name
  def spec(item) = item.crm_product&.specification || item.mes_material&.specification

  # 数值格式化：整数去小数、非整保留原值（Excel 数字格式由样式控制）。
  def fmt_num(num)
    return nil if num.nil?

    d = num.to_d
    d.frac.zero? ? d.to_i : d.to_f
  end

  def xml_escape(value)
    value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub("\n", '&#10;')
  end
end
