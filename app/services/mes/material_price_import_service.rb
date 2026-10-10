# 物料单价表 Excel 导入：物料编码 / 物料名称 / 规格型号 / 单价。
#
# 口径与 BOM 成本表导入一致：
#   1. **只认物料编码**（= 商品档 sku）。名称与规格只是给人对照用，落库不取。
#   2. 对不上商品档的行整行退回，不自动建档——编码写错自动建档只会堆垃圾。
#   3. 已有的按编码覆盖（这张表就是标准价，重导=重定标准），没有的新建。
class Mes::MaterialPriceImportService
  class Error < StandardError; end

  require 'roo'

  HEADER_SCAN_ROWS = 5
  # 各家导出的叫法不一样，常见几种都认。
  SKU_HEADERS = %w[物料编码 商品编码 代码 编码].freeze
  PRICE_HEADERS = %w[单价 标准价 采购单价].freeze

  def initialize(account:, user:, path:)
    @account = account
    @user = user
    @path = path
  end

  def import!
    rows = parse
    raise Error, '文件里没有数据行' if rows.empty?

    @missing = []
    @created = 0
    @updated = 0
    by_sku = products_by_sku(rows)
    ActiveRecord::Base.transaction { rows.each { |row| apply_row(row, by_sku[row[:sku].upcase]) } }

    { rows: rows.size, created: @created, updated: @updated,
      missing_count: @missing.size, missing_skus: @missing.first(50) }
  end

  private

  def products_by_sku(rows)
    @account.crm_products
            .where('upper(trim(sku)) IN (?)', rows.map { |r| r[:sku].upcase })
            .index_by { |p| p.sku.to_s.strip.upcase }
  end

  def apply_row(row, product)
    return @missing << row[:sku] if product.nil?

    rec = @account.mes_material_prices.find_or_initialize_by(crm_product_id: product.id)
    rec.new_record? ? @created += 1 : @updated += 1
    rec.update!(unit_price_micros: row[:price], updated_by: @user)
  end

  def parse
    sheet = open_sheet
    header_row, cols = find_header(sheet)
    raise Error, "表头里找不到「#{SKU_HEADERS.first}」列" if header_row.nil?
    raise Error, "表头里找不到「#{PRICE_HEADERS.first}」列" if cols[:price].nil?

    ((header_row + 1)..sheet.last_row).filter_map do |i|
      sku = sheet.cell(i, cols[:sku]).to_s.strip
      next if sku.blank?

      { sku: sku, price: to_micros(sheet.cell(i, cols[:price])) }
    end
  end

  def open_sheet
    Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
  rescue StandardError => e
    raise Error, "读取 Excel 失败：#{e.message}"
  end

  # 表头不一定在第一行（有的导出带标题行），前几行扫一遍。
  def find_header(sheet)
    (1..[HEADER_SCAN_ROWS, sheet.last_row].min).each do |i|
      cells = (1..sheet.last_column).map { |c| sheet.cell(i, c).to_s.strip }
      sku_col = col_of(cells, SKU_HEADERS)
      next if sku_col.nil?

      return [i, { sku: sku_col, price: col_of(cells, PRICE_HEADERS) }]
    end
    [nil, {}]
  end

  def col_of(cells, names)
    idx = cells.index { |c| names.include?(c) }
    idx && (idx + 1)
  end

  def to_micros(value)
    return 0 if value.blank?

    ((value.to_s.gsub(/[^\d.\-]/, '').to_d) * 1_000_000).round
  rescue ArgumentError
    0
  end
end
