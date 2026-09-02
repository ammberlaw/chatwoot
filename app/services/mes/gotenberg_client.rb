require 'rest-client'
require 'tempfile'

# 文档转 PDF：把公司原始 .xlsx（Mes::PoTemplateFiller 填好、含公章）交给 Gotenberg 的
# LibreOffice 接口转成 1:1 PDF（保公章/排版/中文，模板已设「缩放到一页宽」）。
# Gotenberg 作为独立 sidecar 容器跑（docker-compose 服务名 gotenberg），不往 rails 镜像里塞 LibreOffice。
class Mes::GotenbergClient
  BASE_URL = ENV.fetch('GOTENBERG_URL', 'http://gotenberg:3000').freeze
  CONVERT_TIMEOUT = 60 # 单文件转换超时（秒）

  class ConversionError < StandardError; end

  # xlsx 字节流 → PDF 字节流。filename 仅用于 Gotenberg 识别扩展名（.xlsx）。
  def self.xlsx_to_pdf(xlsx_bytes, filename: 'document.xlsx')
    base = File.basename(filename, '.*')
    file = Tempfile.new([base, '.xlsx'])
    file.binmode
    file.write(xlsx_bytes)
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
