# BOM 成本表 Excel 导入：商品编码 / 产品名称 / 规格型号 / 人工费（旧表头「加工费」也认）/ 制造费用。
#
# 口径与期初库存导入一致：
#   1. **只认商品编码**——产品名称与规格只是给人对照用的，落库不取。
#   2. 对不上产品档案的行**整行退回**，不自动建档：编码写错了自动建档只会往档案里堆垃圾。
#   3. 已有的按编码覆盖（这张表就是标准值，重导=重定标准），没有的新建。
# 制造费用列可以没有（用户第一版的表只有加工费），缺列按 0。
class Erp::BomCostImportService
  class Error < StandardError; end

  require 'roo'

  HEADER_SCAN_ROWS = 5
  SKU_HEADER = '商品编码'.freeze
  # 新旧表头都认：字段 2026-10-28 从「加工费」改叫「人工费」，
  # 但财务手上存着一堆写「加工费」的旧 Excel，只认新名字等于把那些表全废了。
  PROCESS_HEADERS = ['人工费', '加工费'].freeze
  OVERHEAD_HEADERS = ['制造费用'].freeze

  def initialize(account:, user:, path:)
    @account = account
    @user = user
    @path = path
  end

  def import!
    rows = parse
    raise Error, '文件里没有数据行' if rows.empty?

    skus = rows.map { |r| r[:sku] }
    products = @account.crm_products.where('upper(trim(sku)) IN (?)', skus.map(&:upcase)).to_a
    by_sku = products.index_by { |p| p.sku.to_s.strip.upcase }

    missing = []
    created = 0
    updated = 0
    ActiveRecord::Base.transaction do
      rows.each do |row|
        product = by_sku[row[:sku].upcase]
        if product.nil?
          missing << row[:sku]
          next
        end

        rec = @account.erp_bom_costs.find_or_initialize_by(crm_product_id: product.id)
        rec.new_record? ? created += 1 : updated += 1
        rec.update!(process_fee_micros: row[:process], overhead_fee_micros: row[:overhead], updated_by: @user)
      end
    end
    { rows: rows.size, created: created, updated: updated,
      missing_count: missing.size, missing_skus: missing.first(50) }
  end

  private

  def parse
    sheet = open_sheet
    header_row, cols = find_header(sheet)
    raise Error, "表头里找不到「#{SKU_HEADER}」列" if header_row.nil?

    ((header_row + 1)..sheet.last_row).filter_map do |i|
      sku = sheet.cell(i, cols[:sku]).to_s.strip
      next if sku.blank?

      { sku: sku,
        process: to_micros(cols[:process] && sheet.cell(i, cols[:process])),
        overhead: to_micros(cols[:overhead] && sheet.cell(i, cols[:overhead])) }
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
      sku_col = cells.index(SKU_HEADER)
      next if sku_col.nil?

      return [i, { sku: sku_col + 1,
                   process: col_of(cells, PROCESS_HEADERS),
                   overhead: col_of(cells, OVERHEAD_HEADERS) }]
    end
    [nil, {}]
  end

  def col_of(cells, names)
    idx = cells.index { |c| names.include?(c) }
    idx && idx + 1
  end

  def to_micros(value)
    return 0 if value.blank?

    (value.to_s.gsub(/[^\d.\-]/, '').to_d * 1_000_000).round
  rescue ArgumentError
    0
  end
end
