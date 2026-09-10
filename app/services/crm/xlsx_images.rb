# 从 xlsx 里抠出内嵌图片以及它锚定在第几行。
# 为什么要自己解：核价表里的产品图是「浮动图片」，不是单元格的值——roo 只读格子，
# 读出来那一列永远是空的。xlsx 本身是个 zip，图片在 xl/media，锚点在 xl/drawings/*.xml，
# 顺着 workbook → sheet → drawing 三层 rels 就能把「图 ↔ 行」对上。
#
# 返回 { sheet 名 => { 行号(1 基) => [{ bytes:, filename:, content_type: }, ...] } }
class Crm::XlsxImages
  CONTENT_TYPES = { 'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg',
                    'gif' => 'image/gif', 'bmp' => 'image/bmp', 'emf' => 'image/emf' }.freeze

  def self.extract(path)
    new(path).extract
  end

  def initialize(path)
    @path = path
  end

  def extract
    result = {}
    Zip::File.open(@path) do |zip|
      @zip = zip
      sheet_paths(zip).each do |name, sheet_path|
        images = images_for_sheet(sheet_path)
        result[name] = images if images.present?
      end
    end
    result
  rescue StandardError => e
    Rails.logger.warn("[Crm::XlsxImages] #{e.class}: #{e.message}")
    {}
  end

  private

  def read(entry_path)
    @zip.find_entry(entry_path)&.get_input_stream&.read
  end

  # 统一去掉命名空间：xlsx 各文件都带 xdr:/r: 前缀，去掉后用普通 css/属性名取值最省事。
  def xml(entry_path)
    body = read(entry_path)
    return nil if body.nil?

    Nokogiri::XML(body).tap(&:remove_namespaces!)
  end

  # sheet 名 → xl/worksheets/sheetN.xml
  def sheet_paths(_zip)
    book = xml('xl/workbook.xml')
    rels = rel_map('xl/_rels/workbook.xml.rels')
    return {} if book.nil?

    book.css('sheets sheet').to_h do |node|
      target = rels[node['id']]
      [node['name'], target && "xl/#{target.sub(%r{\A/?xl/}, '')}"]
    end.compact
  end

  # rels 文件：Id → Target
  def rel_map(path)
    doc = xml(path)
    return {} if doc.nil?

    doc.css('Relationship').to_h { |r| [r['Id'], r['Target']] }
  end

  def images_for_sheet(sheet_path)
    return {} if sheet_path.blank?

    doc = xml(sheet_path)
    rels = rel_map(rels_path_for(sheet_path))
    drawing_id = doc&.css('drawing')&.first&.[]('id')
    drawing = drawing_id && rels[drawing_id]
    return {} if drawing.blank?

    collect_anchors(normalize(drawing, sheet_path))
  end

  def rels_path_for(path)
    dir = File.dirname(path)
    "#{dir}/_rels/#{File.basename(path)}.rels"
  end

  # drawing 的 Target 是相对 sheet 目录的（../drawings/drawing1.xml）。
  # 只能用 Pathname#cleanpath 做纯路径运算——File.expand_path 会按进程工作目录展开成绝对路径，
  # 拼出来的是 /app/xl/... 在 zip 里根本找不到。
  def normalize(target, base_path)
    return target.delete_prefix('/') if target.start_with?('/')

    Pathname.new(File.dirname(base_path)).join(target).cleanpath.to_s
  end

  def collect_anchors(drawing_path)
    doc = xml(drawing_path)
    return {} if doc.nil?

    rels = rel_map(rels_path_for(drawing_path))
    images = Hash.new { |h, k| h[k] = [] }
    doc.css('twoCellAnchor, oneCellAnchor').each do |anchor|
      row = anchor.css('from row').first&.text.to_i + 1 # xdr 里行号从 0 起
      blob = blob_for(anchor, rels, drawing_path)
      images[row] << blob if blob
    end
    images
  end

  def blob_for(anchor, rels, drawing_path)
    embed = anchor.css('blip').first&.[]('embed')
    target = embed && rels[embed]
    return nil if target.blank?

    media_path = normalize(target, drawing_path)
    bytes = read(media_path)
    return nil if bytes.blank?

    ext = File.extname(media_path).delete('.').downcase
    { bytes: bytes, filename: File.basename(media_path), content_type: CONTENT_TYPES[ext] || 'image/png' }
  end
end
