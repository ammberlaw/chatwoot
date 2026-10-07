# MES 期初库存导入：把金蝶「库存查询表」原样导进 MES 结存。
#
# 为什么必须有：MES 的库存只能由采购收货产生——仓库里实际存在、但没走过系统采购的料，
# 系统里一律是 0（上线时实测 2786 个 SKU 只有 16 个有结存）。而「库存不足」是在**过账时**
# 硬拦的，于是领料单能建、能提交，几天后在仓管那儿过账才炸、错还报在别人屏幕上。
# 期初不导进来，整条领料流程就是死的。
#
# 为什么不拿「原料入库单 + 不关联采购单」顶替：那条路过账会生成「借存货 / 贷应付账款」
# 的凭证，凭空给谁都不是的供应商挂一笔应付。期初走独立用途 OPENING，见 Mes::StockEntry::PURPOSES。
#
# 两条规则与 ERP 的凭证/期初导入一致：
# 1. **有一行错就整份不导**——期初是账的地基，半份进账比不进账更难收拾。
# 2. 重复导入要 replace: true，先作废上一批期初单再建；期初货已被领用导致冲回变负库存时
#    整份回滚并报错，让仓管先处理那些领料单。
class Mes::StockOpeningImportService
  class Error < StandardError; end

  # 金蝶导出前两行是标题和查询条件，表头不在第一行。
  HEADER_SCAN_ROWS = 10
  SKU_HEADER = '商品编码'.freeze
  WAREHOUSE_HEADER = '仓库名称'.freeze
  # 数量列优先「即时库存」；金蝶不同版本的后缀（基本）/（库存）不固定，按前缀认。
  QTY_HEADER_PREFIXES = %w[即时库存 库存数量 结存数量].freeze

  # 金蝶仓名 → MES 已有仓库 code。不映射的话期初会落进一个新建的同义仓，
  # 同一个 SKU 分成两个结存桶，领料按仓库查照样说「库存不足」。
  WAREHOUSE_CODE_ALIASES = { '材料仓' => 'RAW', '产成品仓' => 'FINISHED' }.freeze

  # 成品走销售出库（item_type=PRODUCT），其余走生产领料（item_type=MATERIAL）。
  # 结存表的唯一键带 item_type，记错桶就等于没导。
  FINISHED_CATEGORY = 'FINISHED'.freeze

  Row = Struct.new(:sku, :name, :spec, :warehouse_name, :unit, :qty, :line_no, keyword_init: true)

  def initialize(account:, user:, path:)
    @account = account
    @user = user
    @path = path
  end

  # 预检：只读，返回导入前要让人看清楚的那几个数。
  def preview
    rows = parse
    products = product_map(rows)
    {
      total_rows: rows.size,
      warehouses: warehouse_summary(rows),
      finished_rows: rows.count { |r| products[r.sku]&.category == FINISHED_CATEGORY },
      material_rows: rows.count { |r| products[r.sku] && products[r.sku].category != FINISHED_CATEGORY },
      missing_skus: rows.reject { |r| products[r.sku] }.map(&:sku).uniq,
      existing_opening_entries: existing_openings.count
    }
  end

  # 返回 { entries:, rows:, created_products:, created_warehouses:, replaced_entries: }
  def import!(create_missing_products: false, new_product_line: nil, replace: false)
    rows = parse
    raise Error, '文件里没有数据行' if rows.empty?

    result = nil
    ActiveRecord::Base.transaction do
      replaced = replace ? cancel_existing_openings! : 0
      created_products = ensure_products!(rows, create_missing_products, new_product_line)
      warehouses, created_warehouses = ensure_warehouses!(rows)
      entries = build_entries!(rows, warehouses)
      result = { entries: entries.size, rows: rows.size, created_products: created_products,
                 created_warehouses: created_warehouses, replaced_entries: replaced }
    end
    result
  end

  private

  # ── 读表 ──────────────────────────────────────────────────────

  def parse
    @parse ||= begin
      sheet = Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
      header_row = find_header_row(sheet)
      raise Error, "表头里找不到「#{SKU_HEADER}」列，确认导出的是金蝶「库存查询表」" if header_row.nil?

      idx = column_indexes(sheet, header_row)
      rows = (header_row + 1).upto(sheet.last_row).filter_map { |n| build_row(sheet, idx, n) }
      raise Error, '文件里没有数据行' if rows.empty?

      rows
    end
  end

  def find_header_row(sheet)
    1.upto([HEADER_SCAN_ROWS, sheet.last_row].min) do |n|
      return n if sheet.row(n).any? { |cell| cell.to_s.strip == SKU_HEADER }
    end
    nil
  end

  def column_indexes(sheet, header_row)
    headers = sheet.row(header_row).map { |cell| cell.to_s.strip }
    qty = headers.index { |h| QTY_HEADER_PREFIXES.any? { |prefix| h.start_with?(prefix) } }
    raise Error, "表头里找不到库存数量列（应为「即时库存…」），实际表头：#{headers.compact_blank.join(' / ')}" if qty.nil?

    warehouse = headers.index(WAREHOUSE_HEADER)
    raise Error, "表头里找不到「#{WAREHOUSE_HEADER}」列" if warehouse.nil?

    { sku: headers.index(SKU_HEADER), name: headers.index('商品名称'),
      spec: headers.index('规格型号'), unit: headers.index('基本单位'),
      warehouse: warehouse, qty: qty }
  end

  def build_row(sheet, idx, line_no)
    cells = sheet.row(line_no)
    sku = cells[idx[:sku]].to_s.strip
    return nil if sku.blank?

    qty = cells[idx[:qty]].to_d
    # 0 和负数都不导：0 行没有意义，负数是金蝶那边的账面异常，导进来会直接变成负库存。
    raise Error, "第 #{line_no} 行 #{sku} 的库存是 #{qty}，期初不接受 0 或负数，请先在金蝶核对" if qty <= 0

    warehouse_name = cells[idx[:warehouse]].to_s.strip
    raise Error, "第 #{line_no} 行 #{sku} 没有仓库名称" if warehouse_name.blank?

    Row.new(sku: sku, name: cell(cells, idx[:name]), spec: cell(cells, idx[:spec]),
            unit: cell(cells, idx[:unit]), warehouse_name: warehouse_name, qty: qty, line_no: line_no)
  end

  def cell(cells, index) = index ? cells[index].to_s.strip.presence : nil

  def warehouse_summary(rows)
    summary = rows.group_by(&:warehouse_name).map do |name, group|
      existing = find_warehouse(name)
      { name: name, rows: group.size, maps_to: existing&.name, will_create: existing.nil? }
    end
    summary.sort_by { |row| -row[:rows] }
  end

  # ── 产品档案 ──────────────────────────────────────────────────

  def product_map(rows)
    @product_map ||= @account.crm_products.where(sku: rows.map(&:sku).uniq).index_by(&:sku)
  end

  def ensure_products!(rows, create_missing, fallback_line)
    missing = rows.reject { |row| product_map(rows)[row.sku] }.uniq(&:sku)
    return 0 if missing.empty?

    unless create_missing
      raise Error, "有 #{missing.size} 个编码在产品档案里不存在（如 #{missing.first(5).map(&:sku).join('、')}），" \
                   '请勾选「自动建档」或先补齐档案'
    end

    lines = resolved_product_lines(missing, fallback_line)
    missing.each { |row| @product_map[row.sku] = create_product!(row, lines[row.sku]) }
    missing.size
  end

  # 新建档案的产品线**逐条按同族编码推断**，不是整份用同一个。
  # 编码前两段就是族（M.XC / P.11 / O.1…），生产实测分得干干净净：M./O. 全是商显、P. 全是平板，
  # 而一份金蝶库存表里两条线都有——整份塞同一个产品线必然有一批落错线、在领料选料里看不见。
  # 推断不出来（档案里没有同族）才用调用方传的兜底值。
  def resolved_product_lines(missing, fallback_line)
    dominant = dominant_line_by_family
    lines = missing.to_h { |row| [row.sku, dominant[family_of(row.sku)] || fallback_line.presence] }
    blank = lines.select { |_sku, line| line.blank? }.keys
    # 产品档案搜索是按产品线过滤的，留空的档案切到任一产线都选不到，等于凭空消失。
    raise Error, "这些编码推断不出产品线，请指定：#{blank.first(5).join('、')}" if blank.any?

    lines
  end

  def family_of(sku) = sku.to_s.split('.').first(2).join('.')

  # 一次 pluck 把全部档案的「族 → 产线」算出来。
  # 逐个编码去 LIKE 查是 N+1——生产上 4887 条档案 × 58 个新编码，光这一步就把请求顶过了
  # Rack 的 15s 超时（首次导入即 500，事务整份回滚）。
  def dominant_line_by_family
    tally = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    @account.crm_products.where.not(product_line: nil).pluck(:sku, :product_line).each do |sku, line|
      tally[family_of(sku)][line] += 1
    end
    tally.transform_values { |counts| counts.max_by { |_line, n| n }&.first }
  end

  def create_product!(row, product_line)
    @account.crm_products.create!(
      sku: row.sku, name: row.name.presence || row.sku, specification: row.spec,
      unit: row.unit, category: 'RAW_MAIN', product_line: product_line
    )
  end

  # ── 仓库 ──────────────────────────────────────────────────────

  def find_warehouse(name)
    code = WAREHOUSE_CODE_ALIASES[name]
    return @account.mes_warehouses.find_by(code: code) if code

    @account.mes_warehouses.find_by(name: name)
  end

  def ensure_warehouses!(rows)
    created = 0
    map = rows.map(&:warehouse_name).uniq.index_with do |name|
      existing = find_warehouse(name)
      next existing if existing

      created += 1
      # kind 故意留空：领料/入库弹窗靠 find(kind == 'RAW' / 'FINISHED') 挑默认仓，
      # 新建的仓一旦也标成 RAW，默认仓可能被「不良品仓」之类抢走。需要的话在仓库管理里补。
      @account.mes_warehouses.create!(name: name, code: warehouse_code_for(name))
    end
    [map, created]
  end

  # 仓库 code 账套内唯一，中文仓名转不出可读 code，直接按序号占位（名称才是人看的）。
  def warehouse_code_for(name)
    base = "W#{Digest::MD5.hexdigest(name)[0, 6].upcase}"
    return base unless @account.mes_warehouses.exists?(code: base)

    "#{base}-#{SecureRandom.hex(2).upcase}"
  end

  # ── 建单 ──────────────────────────────────────────────────────

  # 按「仓库 × 产品线」分组建单，不是只按仓库：库存单列表是按产品线过滤的，
  # 一张单混着两条产线就只能落一个 product_line，切到另一条产线那张单就消失了。
  def build_entries!(rows, warehouses)
    rows.group_by { |row| [row.warehouse_name, @product_map[row.sku].product_line] }
        .map { |(warehouse_name, line), group| create_entry!(warehouses[warehouse_name], warehouse_name, line, group) }
  end

  def create_entry!(warehouse, warehouse_name, product_line, group)
    entry = @account.mes_stock_entries.new(
      purpose: 'OPENING', to_warehouse_id: warehouse.id, owner_id: @user&.id, product_line: product_line,
      remark: "期初库存导入（#{warehouse_name}，#{group.size} 行）",
      stock_entry_items_attributes: group.map { |row| item_attrs(row, warehouse) }
    )
    entry.save!
    entry.post!
    entry
  end

  def item_attrs(row, warehouse)
    product = @product_map[row.sku]
    { item_type: product.category == FINISHED_CATEGORY ? 'PRODUCT' : 'MATERIAL',
      crm_product_id: product.id, qty: row.qty, unit: row.unit.presence || product.unit,
      warehouse_id: warehouse.id }
  end

  # ── 重复导入 ──────────────────────────────────────────────────

  def existing_openings = @account.mes_stock_entries.where(purpose: 'OPENING', status: 'POSTED')

  def cancel_existing_openings!
    entries = existing_openings.to_a
    entries.each(&:cancel!)
    # 冲回后出现负结存＝那批期初货已经被领出去了，整份回滚，让仓管先作废相关领料单。
    negative = @account.mes_stock_balances.where('qty < 0').count
    raise Error, "作废上一批期初单后有 #{negative} 条结存变成负数（货已被领用），请先作废相关领料/出库单再重导" if negative.positive?

    entries.size
  end
end
