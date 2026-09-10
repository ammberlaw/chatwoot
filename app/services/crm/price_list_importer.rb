# 把公司现成的核价 Excel 导进系统：一个 sheet = 一条产品线的一张表。
# 各产品线表头差异很大（有的六七列参数、有的按触摸类型横向列价），所以列是从表头行读出来的，
# 不做固定映射；哪些列是价格靠数据判断（该列大部分格能当数字读 = 价格列）。
class Crm::PriceListImporter
  HEADER_SCAN_ROWS = 6      # 表头一般在前几行（前面可能有大标题、报价日期）
  MIN_HEADER_CELLS = 3      # 少于这么多个非空格的行不当表头
  PRICE_RATIO = 0.6         # 该列可解析为数字的比例达到这个值就算价格列
  DROP_LABELS = %w[序号 图片].freeze # 系统里没意义的列
  GENERIC_SHEET = /\A(sheet|工作表)\s*\d*\z/i # 没改过名的 sheet，退回用文件名当产品线
  NOTE_PREFIXES = %w[备注 Remark remark 报价规则 说明].freeze
  # 各产品线的表头叫法不一（配置/产品规格/参数、10台内/1-10台…），同义的统一成一种叫法，
  # 免得十几条产品线摆在一起每张表一个样。真实档位不同的（如平板 10-100/100-500）不动。
  LABEL_ALIASES = {
    '整机名称' => '名称', '配置' => '参数', '产品规格' => '参数',
    '10台内' => '1-10台', '11-199' => '11-199台', '200以上' => '200台以上',
    '100台内' => '1-100台', '触摸类型（选配）' => '触摸类型'
  }.freeze

  Result = Struct.new(:price_list, :sheet, :rows, keyword_init: true)

  def initialize(account:, user:, file:, currency: 'USD')
    @account = account
    @user = user
    @file = file
    @currency = currency
    @fallback_line = line_from_filename(file)
  end

  # 返回 [Result, ...]，每个 sheet 一条（空 sheet 跳过）。
  def call
    book = Roo::Excelx.new(@file.path)
    # 产品图是浮动图片不在格子里，另外从 zip 里按锚点行取（见 Crm::XlsxImages）。
    @images = Crm::XlsxImages.extract(@file.path)
    book.sheets.filter_map { |name| import_sheet(book.sheet(name), name) }
  end

  private

  def import_sheet(sheet, name)
    header_row = find_header_row(sheet)
    return nil if header_row.nil?

    cols, indexes = build_columns(sheet, header_row)
    return nil if cols.empty?

    rows = data_rows(sheet, header_row, indexes)
    return nil if rows.empty?

    cols, rows = drop_blank_columns(cols, rows)
    return nil if cols.empty?

    cols = unify_labels(cols)

    line = name.to_s.match?(GENERIC_SHEET) ? @fallback_line : name
    list = create_list(line: line, cols: cols, rows: rows,
                       note: sheet_title(sheet, header_row), sheet_name: name)
    Result.new(price_list: list, sheet: name, rows: rows.size)
  end

  # 「D系列报价单2026-3-1.xlsx」→「D系列」：去掉扩展名、报价单/核价表字样和日期。
  def line_from_filename(file)
    base = File.basename(file.try(:original_filename) || file.path.to_s, '.*')
    base.sub(/[\d.\-年月日\s]*\z/, '').sub(/(报价单|核价表|价格表).*\z/, '').strip.presence || base
  end

  # 表头 = 前几行里「第一行达到最少格数」的那行。不能取格子最多的行——表头常有合并单元格，
  # 非空格反而比数据行少，取最多会把第一条数据当成表头。
  def find_header_row(sheet)
    (1..[HEADER_SCAN_ROWS, sheet.last_row.to_i].min).find do |r|
      row_values(sheet, r).count(&:present?) >= MIN_HEADER_CELLS
    end
  end

  def row_values(sheet, row)
    (1..sheet.last_column.to_i).map { |c| cell_text(sheet.cell(row, c)) }
  end

  # 建列：丢掉空表头、序号/图片这类列，以及整列没数据的列（如空着的「图片」）。
  def build_columns(sheet, header_row)
    kept = row_values(sheet, header_row).each_with_index.filter_map do |label, i|
      col = keep_column(sheet, header_row, label, i + 1)
      col && [col, i + 1]
    end
    [kept.map(&:first), kept.map(&:last)]
  end

  # 该列要不要收：表头空的、序号/图片这类、整列没数据的都跳过。
  def keep_column(sheet, header_row, label, col_index)
    return nil if label.blank? || DROP_LABELS.any? { |d| label.include?(d) }

    values = column_values(sheet, header_row, col_index)
    return nil if values.all?(&:blank?)

    { 'label' => label, 'type' => price_column?(values) ? 'price' : 'text' }
  end

  def column_values(sheet, header_row, col)
    ((header_row + 1)..sheet.last_row.to_i).map { |r| cell_text(sheet.cell(r, col)) }
  end

  def price_column?(values)
    filled = values.reject(&:blank?)
    return false if filled.empty?

    numeric = filled.count { |v| Float(v.to_s.delete('$¥, '), exception: false) }
    numeric.to_f / filled.size >= PRICE_RATIO
  end

  # 数据行：表头之后到「备注/Remarks」那类整行说明为止；合并单元格造成的空格从上一行补齐。
  def data_rows(sheet, header_row, indexes)
    carried = Array.new(indexes.size)
    rows = []
    ((header_row + 1)..sheet.last_row.to_i).each do |r|
      values = indexes.map { |c| cell_text(sheet.cell(r, c)) }
      next if values.all?(&:blank?)
      break if note_row?(values)

      rows << [r, carry_forward(values, carried)]
    end
    rows
  end

  # 同义列名归一；若归一后的名字这张表里已经有了就保持原样（避免出现两列同名）。
  def unify_labels(cols)
    taken = cols.pluck('label')
    cols.map do |c|
      target = LABEL_ALIASES[c['label']]
      next c if target.blank? || taken.include?(target)

      taken << target
      c.merge('label' => target)
    end
  end

  # 数据行里整列都空的列直接丢掉（如 D/L 系列那个从头到尾没填的「款式」）。
  # 建列时是按整列扫的，表尾说明行里偶尔有字会让空列被留下，这里按真实数据行再筛一次。
  def drop_blank_columns(cols, rows)
    keep = cols.each_index.select { |i| rows.any? { |(_r, values)| values[i].to_s.strip.present? } }
    return [cols, rows] if keep.size == cols.size

    [keep.map { |i| cols[i] }, rows.map { |(r, values)| [r, keep.map { |i| values[i] }] }]
  end

  # 合并单元格在 Excel 里只有左上角有值，其余行读出来是空的——从上一行补齐，
  # 让每一行都自带完整信息（尺寸/名称这类列尤其需要）。
  def carry_forward(values, carried)
    values.each_with_index.map do |v, i|
      carried[i] = v if v.present?
      (v.presence || carried[i]).to_s
    end
  end

  # 只有第一格有一长段文字 = 表尾说明，不是数据行。
  def note_row?(values)
    first = values.first.to_s
    values.drop(1).all?(&:blank?) && (first.length > 12 || NOTE_PREFIXES.any? { |p| first.start_with?(p) })
  end

  def cell_text(value)
    case value
    when nil then ''
    when Float then value == value.to_i ? value.to_i.to_s : format('%.2f', value)
    when Date, DateTime, Time then value.strftime('%Y-%m-%d')
    else strip_markup(value.to_s)
    end
  end

  # 富文本格（表头里加粗/换行）被 roo 读成带 <html><b> 的字符串，去掉标签只留文字。
  def strip_markup(text)
    text.include?('<') ? text.gsub(/<[^>]*>/, '').strip : text.strip
  end

  def create_list(line:, cols:, rows:, note:, sheet_name:)
    list = @account.crm_price_lists.create!(
      title: "#{line}报价单", product_line: line, currency: @currency,
      columns: cols, effective_on: Date.current, status: 'DRAFT',
      header_note: note, creator: @user
    )
    sheet_images = @images[sheet_name] || {}
    rows.each_with_index do |(row_no, values), i|
      item = list.items.create!(account_id: @account.id, position: i, values: values)
      attach_image(item, sheet_images[row_no])
    end
    list
  end

  def attach_image(item, images)
    picture = Array(images).first
    return if picture.blank?

    item.image.attach(io: StringIO.new(picture[:bytes]), filename: picture[:filename],
                      content_type: picture[:content_type])
  rescue StandardError => e
    Rails.logger.warn("[Crm::PriceListImport] 挂图失败 item=#{item.id}: #{e.message}")
  end

  # 表头之上那一两行（大标题 / 报价日期）留作表头备注。
  def sheet_title(sheet, header_row)
    (1...header_row).map { |r| row_values(sheet, r).reject(&:blank?).join(' ') }.reject(&:blank?).join("\n").presence
  end
end
