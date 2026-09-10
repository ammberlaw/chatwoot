# 读取 PI（形式发票）自动填单：把上传的 PDF/Excel 抽成文本 → DeepSeek 字段化 →
# 客户名在「本业务员名下客户」里模糊匹配（匹配不上留空，由人工在下拉里补，不新建客户）。
# 只做识别，不落库；结果交前端校对后再建订单。
class Crm::PiParseService
  class UnsupportedType < StandardError; end

  def initialize(account:, user:, file:)
    @account = account
    @user = user
    @file = file
  end

  # 从「已上传的附件」识别（客户文件页传的 PI、历史附件批量补录都走这里）。
  # 识别逻辑只认 tempfile/original_filename/content_type，这里把 blob 落成临时文件套上同款外壳。
  UploadedBlob = Struct.new(:tempfile, :original_filename, :content_type)

  def self.from_attachment(account:, user:, attachment:)
    blob = attachment.blob
    tmp = Tempfile.new(['pi-attachment', File.extname(blob.filename.to_s)], binmode: true)
    tmp.write(blob.download)
    tmp.rewind
    file = UploadedBlob.new(tmp, blob.filename.to_s, blob.content_type.to_s)
    new(account: account, user: user, file: file)
  end

  # 文件名像不像 PI：`pi` 作为独立词出现（避免 shipping 这种词内命中），或含 proforma。
  PI_NAME_RE = /(^|[^a-z])pi([^a-z]|$)|proforma/i

  def self.pi_like_filename?(name)
    PI_NAME_RE.match?(name.to_s.downcase)
  end

  def call
    text = extract_text
    raise UnsupportedType, 'PI 内容为空或无法识别，请确认文件' if text.blank?

    data = Crm::EmailAiService.new(account: @account).pi_extract(text: text)
    build_result(data)
  end

  private

  def extract_text
    case file_kind
    when :pdf then extract_pdf
    when :excel then extract_excel
    else
      raise UnsupportedType, '只支持 PDF 或 Excel（.xlsx/.csv）；老版 .xls 请另存为 .xlsx'
    end
  end

  # 优先按扩展名判类型，缺扩展名时兜底看 content_type。
  def file_kind
    name = @file.original_filename.to_s.downcase
    return :pdf if name.end_with?('.pdf')
    return :excel if name.end_with?('.xlsx', '.csv')
    raise UnsupportedType, '老版 .xls 请先另存为 .xlsx 再上传' if name.end_with?('.xls')

    ct = @file.content_type.to_s
    return :pdf if ct.include?('pdf')
    return :excel if ct.include?('sheet') || ct.include?('csv')

    :unknown
  end

  def extract_pdf
    reader = PDF::Reader.new(@file.tempfile.path)
    reader.pages.map(&:text).join("\n").strip
  end

  # Excel/CSV：逐 sheet 逐行把非空单元格用 ' | ' 拼成一行，喂给模型理解表格。
  def extract_excel
    ext = @file.original_filename.to_s.downcase.end_with?('.csv') ? :csv : :xlsx
    ss = Roo::Spreadsheet.open(@file.tempfile.path, extension: ext)
    ss.sheets.flat_map { |name| sheet_rows(ss.sheet(name)) }.reject(&:blank?).join("\n")
  end

  def sheet_rows(sheet)
    return [] if sheet.first_row.nil?

    (sheet.first_row..sheet.last_row).map do |r|
      (sheet.first_column..sheet.last_column)
        .map { |c| sheet.cell(r, c).to_s.strip }
        .reject(&:blank?)
        .join(' | ')
    end
  end

  def build_result(data)
    raw_name = data['customer_name'].to_s.strip
    matched = match_customer(raw_name)
    line_items = Array(data['line_items']).filter_map { |li| clean_item(li) }
    {
      pi_no: data['pi_no'].presence,
      name: order_name(raw_name, data['pi_no']),
      order_date: normalize_date(data['order_date']),
      delivery_date: normalize_date(data['delivery_date']),
      currency: normalize_currency(data['currency']),
      amount: sane_total(numeric(data['total_amount']), line_items),
      customer: {
        raw_name: raw_name.presence,
        matched_id: matched&.id,
        matched_name: matched&.name
      },
      line_items: line_items
    }
  end

  # 防呆：AI 偶发把总额多写个 0（10×）等误识别。明细存在且 AI 总额 > 明细合计 3 倍时，
  # 判为误识别、改用明细合计（正常含运费的总额一般只比货值高 10~50%，不会到 3 倍）。
  def sane_total(ai_total, line_items)
    items_sum = line_items.sum { |li| li['amount'].to_f }
    return ai_total unless items_sum.positive?
    return items_sum if ai_total.nil? || ai_total > items_sum * 3

    ai_total
  end

  # 只在「本业务员名下客户」里匹配（与新建订单下拉同口径）：先归一化全等，再互相包含。
  def match_customer(raw)
    return nil if raw.blank?

    key = normalize(raw)
    return nil if key.blank?

    candidates = @account.crm_customers.owned_by(@user.id).select(:id, :name).limit(3000).to_a
    candidates.find { |c| normalize(c.name) == key } ||
      candidates.find do |c|
        n = normalize(c.name)
        n.present? && (n.include?(key) || key.include?(n))
      end
  end

  def normalize(str)
    str.to_s.downcase.gsub(/[^a-z0-9\p{Han}]/, '')
  end

  # 订单名称只取客户名（PI 号有独立字段，不再拼进来）；无客户名时退回 PI 号，再退回占位。
  def order_name(raw_name, pi_no)
    raw_name.presence || pi_no.presence || 'PI 订单'
  end

  def normalize_date(value)
    return nil if value.blank?

    Date.parse(value.to_s).strftime('%Y-%m-%d')
  rescue ArgumentError
    nil
  end

  def normalize_currency(value)
    code = value.to_s.strip.upcase
    Crm::Customer::CURRENCIES.include?(code) ? code : nil
  end

  def clean_item(item)
    return nil unless item.is_a?(Hash)

    name = item['name'].to_s.strip
    return nil if name.blank?

    {
      'name' => name,
      'spec' => item['spec'].to_s.strip,
      'quantity' => numeric(item['quantity']),
      'unit_price' => numeric(item['unit_price']),
      'amount' => numeric(item['amount'])
    }
  end

  # 去掉货币符号/逗号只留数字；整数就返回整数，避免前端出现 1234.0。
  def numeric(value)
    return nil if value.nil?

    str = value.to_s.gsub(/[^0-9.\-]/, '')
    return nil if str.blank?

    num = str.to_f
    (num % 1).zero? ? num.to_i : num
  end
end
