require 'rest-client'
require 'tempfile'
require 'tmpdir'
require 'fileutils'

# 文档转 PDF：把公司原始 .xlsx（Mes::PoTemplateFiller 填好、含公章）交给 Gotenberg 的
# LibreOffice 接口转成 1:1 PDF（保公章/排版/中文，模板已设「缩放到一页宽」）。
# Gotenberg 作为独立 sidecar 容器跑（docker-compose 服务名 gotenberg），不往 rails 镜像里塞 LibreOffice。
class Mes::GotenbergClient
  BASE_URL = ENV.fetch('GOTENBERG_URL', 'http://gotenberg:3000').freeze
  CONVERT_TIMEOUT = 60 # 单文件转换超时（秒）

  class ConversionError < StandardError; end

  # HTML 字符串 → PDF 字节流（走 Chromium 路由）。用于系统内自己排版的单据，
  # 如 CRM 核价表导出——版式在 HTML/CSS 里控，不依赖 Excel 模板。
  # ⚠ Chromium 路由要求主文件名必须是 index.html（否则 400），所以建临时目录再按名写文件，
  # 不能用 Tempfile（它会带随机后缀）。
  def self.html_to_pdf(html, landscape: false, margin: '0.6')
    dir = Dir.mktmpdir
    path = File.join(dir, 'index.html')
    File.write(path, html)
    file = File.open(path, 'rb')
    RestClient::Request.execute(
      method: :post, url: "#{BASE_URL}/forms/chromium/convert/html",
      payload: chromium_payload(file, landscape, margin),
      timeout: CONVERT_TIMEOUT, open_timeout: 10
    ).body
  rescue RestClient::Exception => e
    raise ConversionError, "PDF 生成失败（#{e.http_code}）：#{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    raise ConversionError, "PDF 生成服务不可用：#{e.message}"
  ensure
    file&.close
    FileUtils.remove_entry(dir) if dir
  end

  def self.chromium_payload(file, landscape, margin)
    { files: file, landscape: landscape.to_s, printBackground: 'true',
      marginTop: margin, marginBottom: margin, marginLeft: margin, marginRight: margin }
  end
  private_class_method :chromium_payload

  # xlsx 字节流 → PDF 字节流。filename 仅用于 Gotenberg 识别扩展名（.xlsx）。
  def self.xlsx_to_pdf(xlsx_bytes, filename: 'document.xlsx')
    office_to_pdf(xlsx_bytes, filename: filename)
  end

  # 多份 Office 文档 → **一个** PDF（LibreOffice 路由的 merge=true，按传入顺序拼页）。
  # 采购单按供应商拆成多份后用它合成一份：11 家供应商原来是 11 个文件打 zip，
  # 下载完还要解压、一个个开。docs = [[filename, bytes], ...]
  def self.office_to_pdf_merged(docs)
    return office_to_pdf(docs.first[1], filename: docs.first[0]) if docs.size == 1

    files = docs.map do |filename, bytes|
      ext = File.extname(filename.to_s).presence || '.xlsx'
      base = File.basename(filename.to_s, '.*').presence || 'document'
      f = Tempfile.new([base, ext])
      f.binmode
      f.write(bytes)
      f.rewind
      f
    end
    RestClient::Request.execute(
      method: :post, url: "#{BASE_URL}/forms/libreoffice/convert",
      payload: { files: files, merge: 'true' },
      timeout: CONVERT_TIMEOUT * 3, open_timeout: 10
    ).body
  rescue RestClient::Exception => e
    raise ConversionError, "PDF 合并失败（#{e.http_code}）：#{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    raise ConversionError, "PDF 转换服务不可用：#{e.message}"
  ensure
    files&.each { |f| f.close; f.unlink }
  end

  # 任意 Office 文档字节流 → PDF 字节流（LibreOffice 路由，按扩展名识别格式）。
  # 除了导出单据，也用于「读不了的老格式」降级取文字：老版 .xls 没有纯 Ruby 解析器，
  # 转成 PDF 再抽文字比往镜像里塞一套 BIFF 解析依赖划算（见 Crm::PiParseService）。
  def self.office_to_pdf(bytes, filename: 'document.xlsx')
    ext = File.extname(filename.to_s).presence || '.xlsx'
    base = File.basename(filename.to_s, '.*').presence || 'document'
    file = Tempfile.new([base, ext])
    file.binmode
    file.write(bytes)
    file.rewind
    response = RestClient::Request.execute(
      method: :post,
      url: "#{BASE_URL}/forms/libreoffice/convert",
      payload: { files: file },
      timeout: CONVERT_TIMEOUT,
      open_timeout: 10
    )
    response.body
  rescue RestClient::Exception => e
    raise ConversionError, "PDF 转换失败（#{e.http_code}）：#{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    raise ConversionError, "PDF 转换服务不可用：#{e.message}"
  ensure
    file&.close
    file&.unlink
  end
end
