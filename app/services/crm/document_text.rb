# 把一个文件抽成纯文本。PDF / Excel / CSV / Word 都走这里。
#
# 为什么单独一个服务：原来这套抽取逻辑长在 Crm::PiParseService 里，是 PI 自动填单的
# 私有方法。现在知识库要把认证报告、规格书抽成可搜索正文（AI 答产品问题全靠它），
# 用的是同一套解析——两处真实需求，才把它拎出来共用，PiParseService 改为调这里。
#
# 实测（2026-10-28，生产库 40 份知识库 PDF 抽样）：39 份抽出 1400~3400 字正文，
# 1 份抽不出——那份是「已转曲」的画册，文字被转成矢量路径，本来就没有文字层。
# 所以「抽不出」是正常结果而不是故障，调用方要能区分这两种。
class Crm::DocumentText
  class UnsupportedType < StandardError; end

  # 识别只认 tempfile/original_filename/content_type 三样，blob 和上传文件套同一个壳。
  Wrapped = Struct.new(:tempfile, :original_filename, :content_type)

  def self.from_blob(blob)
    tmp = Tempfile.new(['doctext', File.extname(blob.filename.to_s)], binmode: true)
    tmp.write(blob.download)
    tmp.rewind
    new(Wrapped.new(tmp, blob.filename.to_s, blob.content_type.to_s))
  end

  def initialize(file)
    @file = file
  end

  # 认得出类型就抽，抽不出内容返回空串；类型压根不支持才抛 UnsupportedType。
  def call
    case kind
    when :pdf then from_pdf(@file.tempfile.path)
    when :excel then from_excel
    when :office then via_gotenberg
    else
      raise UnsupportedType, '只支持 PDF / Excel(.xls/.xlsx/.csv) / Word(.doc/.docx)'
    end
  end

  # 能不能抽——批量补录前先问一句，省得为 728 个 mp4 各起一个任务。
  def self.extractable?(filename, content_type)
    new(Wrapped.new(nil, filename.to_s, content_type.to_s)).kind != :unknown
  end

  def kind
    name = @file.original_filename.to_s.downcase
    return :pdf if name.end_with?('.pdf')
    return :excel if name.end_with?('.xlsx', '.csv')
    return :office if name.end_with?('.xls', '.doc', '.docx', '.ppt', '.pptx')

    by_content_type
  end

  private

  def by_content_type
    ct = @file.content_type.to_s
    return :pdf if ct.include?('pdf')
    return :excel if ct.include?('spreadsheetml') || ct.include?('csv')
    return :office if ct.include?('ms-excel') || ct.include?('msword') ||
                      ct.include?('wordprocessingml') || ct.include?('presentationml')

    :unknown
  end

  def from_pdf(path)
    PDF::Reader.new(path).pages.map(&:text).join("\n").strip
  end

  # Excel/CSV：逐 sheet 逐行把非空单元格用 ' | ' 拼成一行。
  # roo 读 xlsx 是整张表一次性解析的，一个坏单元格（WPS 老模板导出的「声明成数字型
  # 但值是空的」格子）就能让整个文件读不出来，所以翻车就退回 Gotenberg 转 PDF。
  def from_excel
    ext = @file.original_filename.to_s.downcase.end_with?('.csv') ? :csv : :xlsx
    ss = Roo::Spreadsheet.open(@file.tempfile.path, extension: ext)
    ss.sheets.flat_map { |name| sheet_rows(ss.sheet(name)) }.reject(&:blank?).join("\n")
  rescue StandardError => e
    raise if ext == :csv

    Rails.logger.warn("[doc text] roo 读 xlsx 失败（#{e.class}: #{e.message}），改用 Gotenberg 转 PDF")
    via_gotenberg
  end

  # 老版 .xls(BIFF)、Word、PPT：借已在跑的 Gotenberg（LibreOffice sidecar）转 PDF 再抽。
  def via_gotenberg
    @file.tempfile.rewind
    pdf = Mes::GotenbergClient.office_to_pdf(@file.tempfile.read, filename: @file.original_filename.to_s)
    tmp = Tempfile.new(['doctext-conv', '.pdf'], binmode: true)
    tmp.write(pdf)
    tmp.close
    from_pdf(tmp.path)
  rescue Mes::GotenbergClient::ConversionError => e
    raise UnsupportedType, "#{File.extname(@file.original_filename.to_s).presence || '该格式'} 转换失败：#{e.message}"
  ensure
    tmp&.unlink
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
end
