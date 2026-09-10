# 核价表导出 PDF：版式照公司原来的核价表还原——居中标题、阶梯价合并表头、
# 表头备注、报价规则说明、右下角落款。HTML/CSS 排版后交给 Gotenberg 的 Chromium 转 PDF。
class Crm::PriceListPdf
  SYMBOLS = { 'USD' => '$', 'CNY' => '¥', 'EUR' => '€' }.freeze
  # 公司 logo（与 PI 单据同一份）。Gotenberg 渲染时拿不到站内 URL，必须内嵌成 data URI。
  LOGO_PATH = Rails.public_path.join('brand-assets/pi-logo.png').freeze

  def initialize(price_list:)
    @list = price_list
  end

  def render
    Mes::GotenbergClient.html_to_pdf(html, landscape: true)
  end

  private

  def symbol = SYMBOLS.fetch(@list.currency, '')

  def cols = @list.column_defs

  # 价格列：能当数字读的补币种符号并对齐两位小数；填的是「面议」「/」这类文字就原样出。
  def cell_text(value, type)
    text = value.to_s.strip
    return esc(text) unless type == 'price' && text.present?

    num = Float(text, exception: false)
    num ? "#{symbol}#{format('%.2f', num)}" : esc(text)
  end

  def esc(text) = ERB::Util.html_escape(text.to_s)

  def logo_data_uri
    return @logo_data_uri if defined?(@logo_data_uri)

    @logo_data_uri = nil
    return @logo_data_uri unless File.exist?(LOGO_PATH)

    @logo_data_uri = "data:image/png;base64,#{Base64.strict_encode64(File.binread(LOGO_PATH))}"
  end

  # 备注/规则里的换行在 PDF 里要保留，转成 <br>。
  def multiline(text) = esc(text).gsub("\n", '<br>')

  def html
    <<~HTML
      <!doctype html>
      <html lang="zh-CN"><head><meta charset="utf-8"><style>#{styles}</style></head>
      <body>
        <div class="head">
          #{logo_data_uri ? "<img class=\"logo\" src=\"#{logo_data_uri}\" alt=\"\">" : ''}
          <h1>#{esc(@list.title)}</h1>
        </div>
        <table>
          <thead>
            <tr>
              #{'<th class="col-img">图片</th>' if with_images?}
              #{cols.map { |c| "<th class=\"#{c['type'] == 'price' ? 'col-price' : 'col-text'}\">#{esc(c['label'])}</th>" }.join}
            </tr>
          </thead>
          <tbody>
            #{note_row}
            #{@list.items.ordered.map { |item| item_row(item) }.join}
          </tbody>
        </table>
        #{rules_block}
        <div class="footer">#{multiline(@list.footer_name)}<br>#{@list.effective_on&.strftime('%Y.%-m.%-d')}</div>
      </body></html>
    HTML
  end

  def note_row
    return '' if @list.header_note.blank?

    span = cols.size + (with_images? ? 1 : 0)
    "<tr class=\"note\"><td colspan=\"#{span}\">#{multiline(@list.header_note)}</td></tr>"
  end

  def item_row(item)
    cells = cols.each_with_index.map do |c, i|
      klass = c['type'] == 'price' ? 'price' : 'text'
      "<td class=\"#{klass}\">#{cell_text(item.values[i], c['type'])}</td>"
    end.join
    "<tr>#{image_cell(item) if with_images?}#{cells}</tr>"
  end

  # 有图的行才有图；产品图内嵌成 data URI，PDF 发出去也能看。
  def with_images?
    return @with_images if defined?(@with_images)

    @with_images = @list.items.any? { |i| i.image.attached? }
  end

  def image_cell(item)
    return '<td class="img"></td>' unless item.image.attached?

    data = Base64.strict_encode64(item.image.download)
    "<td class=\"img\"><img src=\"data:#{item.image.content_type};base64,#{data}\"></td>"
  rescue StandardError
    '<td class="img"></td>'
  end

  def rules_block
    return '' if @list.rules_note.blank?

    "<div class=\"rules\">#{multiline(@list.rules_note)}</div>"
  end

  def styles
    <<~CSS
      * { box-sizing: border-box; }
      body { font-family: "Noto Sans CJK SC", "Source Han Sans SC", "Microsoft YaHei", sans-serif;
             font-size: 9px; color: #111; margin: 0; }
      .head { position: relative; margin-bottom: 8px; min-height: 28px; }
      .logo { position: absolute; left: 0; top: 0; height: 28px; }
      h1 { text-align: center; font-size: 16px; margin: 4px 0 0; letter-spacing: 2px; }
      table { width: 100%; border-collapse: collapse; }
      th, td { border: 1px solid #999; padding: 3px 6px; vertical-align: middle; }
      th { background: #f2f2f2; text-align: center; font-weight: 600; }
      .col-price { width: 12%; }
      .col-img { width: 62px; }
      td.img { text-align: center; padding: 2px; }
      td.img img { max-width: 56px; max-height: 44px; object-fit: contain; }
      td.text { font-size: 8px; line-height: 1.35; }
      td.price { text-align: center; white-space: nowrap; }
      /* 第一列通常是型号/名称，居中加粗更像原表 */
      td.text:first-child { text-align: center; font-weight: 600; }
      tr.note td { background: #fffdf3; font-size: 8px; line-height: 1.5; text-align: left; }
      .rules { margin-top: 7px; font-size: 8px; line-height: 1.6; white-space: normal; }
      .footer { margin-top: 10px; text-align: right; font-size: 8px; line-height: 1.5; }
    CSS
  end
end
