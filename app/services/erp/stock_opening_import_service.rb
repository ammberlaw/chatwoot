# 成品期初存货导入（CSV）。启用 FIFO 核算时把金蝶里现有的成品批次一次性搬进来。
#
# 表头（第一行，中文，顺序不限）：
#   商品编码 | 仓库 | 数量 | 单价 | 入库日期 | 备注
#
# 为什么要「入库日期」：FIFO 按进货先后消耗，日期就是排序键。金蝶导出的期初通常带批次日期，
# 照填即可；实在没有就填启用日，那样期初这批会被当成同一批（后续新进的货排在它后面）。
#
# 两条规则与凭证导入一致：
# 1. **有一行错就整份不导**——期初是账的地基，半份进账比不进账更难收拾。
# 2. 重复导入会**先清掉上次导入的期初层**再建，避免越导越多；已经被出库消耗过的期初层清不掉
#    （货都发了），这时直接报错让财务先作废相关出库单。
class Erp::StockOpeningImportService
  class Error < StandardError; end

  SOURCE_TYPE = 'Erp::OpeningInventory'.freeze
  HEADERS = {
    '商品编码' => :sku, '仓库' => :warehouse, '数量' => :qty,
    '单价' => :unit_cost, '入库日期' => :received_at, '备注' => :remark
  }.freeze
  REQUIRED = %w[商品编码 仓库 数量 单价].freeze

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 返回 { created:, total_qty:, total_amount_micros: }
  def import!(csv_text)
    rows = parse(csv_text)
    raise Error, 'CSV 里没有数据行' if rows.empty?

    prepared = rows.each_with_index.map { |row, index| prepare(row, index + 2) }
    ActiveRecord::Base.transaction do
      purge_previous!
      prepared.each { |attrs| @account.erp_stock_layers.create!(attrs) }
    end
    summarize(prepared)
  end

  def self.template_csv
    CSV.generate(encoding: 'UTF-8') do |csv|
      csv << HEADERS.keys
      csv << ['TAB-101-A', '成品仓', '40', '875.00', '2026-08-31', '金蝶期初结转']
    end
  end

  private

  def parse(csv_text)
    table = CSV.parse(csv_text.sub("\xEF\xBB\xBF", ''), headers: true)
    missing = REQUIRED - table.headers.compact.map(&:strip)
    raise Error, "CSV 缺少必需列：#{missing.join('、')}" if missing.any?

    table.filter_map { |row| normalize(row) }
  end

  def normalize(row)
    mapped = HEADERS.to_h { |cn, key| [key, row[cn]&.strip] }
    return nil if mapped.values.all?(&:blank?)

    mapped
  end

  def prepare(row, line_no)
    product = @account.crm_products.find_by(sku: row[:sku])
    raise Error, "第 #{line_no} 行：商品编码「#{row[:sku]}」在产品档案里找不到" if product.blank?

    warehouse = @account.mes_warehouses.find_by(name: row[:warehouse])
    raise Error, "第 #{line_no} 行：仓库「#{row[:warehouse]}」不存在" if warehouse.blank?

    qty = row[:qty].to_s.delete(',').to_d
    raise Error, "第 #{line_no} 行：数量必须大于 0" if qty <= 0

    build_attrs(row, product, warehouse, qty, line_no)
  end

  def build_attrs(row, product, warehouse, qty, line_no)
    unit_cost = (row[:unit_cost].to_s.delete(',').to_d * 1_000_000).round
    raise Error, "第 #{line_no} 行：单价不能为负" if unit_cost.negative?

    {
      crm_product_id: product.id, warehouse_id: warehouse.id,
      qty_in: qty, qty_remaining: qty, unit_cost_micros: unit_cost,
      received_at: parse_date(row[:received_at], line_no),
      source_type: SOURCE_TYPE, remark: row[:remark].presence || '期初存货导入'
    }
  end

  def parse_date(value, line_no)
    return Time.zone.today if value.blank?

    Date.parse(value)
  rescue ArgumentError
    raise Error, "第 #{line_no} 行：入库日期「#{value}」格式不对（用 2026-08-31 这样的写法）"
  end

  # 重导先清旧期初层；已被消耗的清不掉（货已发出，清掉会让已出库的成本失去来源）。
  def purge_previous!
    layers = @account.erp_stock_layers.where(source_type: SOURCE_TYPE)
    consumed = layers.where('qty_remaining < qty_in')
    if consumed.exists?
      raise Error, "已有 #{consumed.count} 条期初批次被出库消耗过，不能重导；" \
                   '请先作废相关出库单，或改用手工补层调整差异'
    end

    layers.destroy_all
  end

  def summarize(prepared)
    {
      created: prepared.size,
      total_qty: prepared.sum { |a| a[:qty_in] }.to_f,
      total_amount_micros: prepared.sum { |a| (a[:qty_in] * a[:unit_cost_micros]).round }
    }
  end
end
