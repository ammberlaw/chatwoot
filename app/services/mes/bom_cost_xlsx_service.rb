# 生产任务单成本导出（财务月度核算底稿）。
#
# 财务原来的流程：导出任务单 → 去采购单里一颗颗查价 → 手工算单台成本，一个月几十张单
# 重复几十遍。这个导出把「查价」和「算」都做掉，一次给全月：
#
#   汇总页  一单一行：单号/日期/型号/数量/材料/人工/制造费用/单台成本/缺价行数
#   明细页  每单每行物料：行号/代码/名称/规格/单位/用量/单价/金额/价源
#
# **缺价行数是刻意放在汇总页上的**：单价覆盖不可能 100%（物料单价表没补齐之前更低），
# 一个不标缺口的合计会被当成完整成本用。宁可让她看见「这单还有 6 行没价」。
class Mes::BomCostXlsxService
  SUMMARY_HEADERS = %w[生产任务单号 投单日期 型号 数量 单位
                       材料成本 生产人工 制造费用 单台成本 缺价行数 备注].freeze
  SUMMARY_WIDTHS = [18, 12, 22, 10, 6, 14, 12, 12, 14, 10, 24].freeze

  DETAIL_HEADERS = %w[生产任务单号 行号 代码 物料名称 规格型号
                      单位 用量 单价 金额 价源].freeze
  DETAIL_WIDTHS = [18, 6, 14, 22, 36, 6, 10, 12, 14, 10].freeze

  # orders: Mes::ProductionOrder 集合（已按权限/筛选收口好）；label: 标题里的范围说明
  def initialize(account:, orders:, label: nil)
    @account = account
    @orders = orders.to_a.select(&:bom_id)
    @label = label
  end

  def to_stream
    XlsxWriter.new(sheets: [
                     { name: '汇总', col_widths: SUMMARY_WIDTHS, rows: summary_rows,
                       merges: ["A1:#{XlsxWriter.col_letter(SUMMARY_HEADERS.size - 1)}1"] },
                     { name: '用料明细', col_widths: DETAIL_WIDTHS, rows: detail_rows,
                       merges: ["A1:#{XlsxWriter.col_letter(DETAIL_HEADERS.size - 1)}1"] }
                   ]).to_stream
  end

  private

  # 每张单算一次价，汇总页和明细页共用，别算两遍。
  def costed
    @costed ||= @orders.map { |order| cost_for(order) }
  end

  def cost_for(order)
    items = order.bom.bom_items.order(:id).to_a
    prices = Mes::MaterialPriceResolver.new(account: @account, items: items, production_order: order).perform
    std = bom_costs[order.bom.crm_product_id]

    { order: order, items: items, prices: prices,
      material: material_total(items, prices),
      process: std&.process_fee_micros.to_i, overhead: std&.overhead_fee_micros.to_i,
      qty: order.bom.base_qty.to_d, unpriced: items.size - prices.size }
  end

  def material_total(items, prices)
    items.sum { |i| prices[i.id] ? (i.qty.to_d * prices[i.id][:price_micros]).round : 0 }
  end

  def bom_costs
    @bom_costs ||= @account.erp_bom_costs.index_by(&:crm_product_id)
  end

  # 单台成本 = 材料 ÷ 基准产量 + 加工费 + 制造费用。
  # 加工费和制造费用本来就是「每台多少」，不用再除。
  def unit_cost(row)
    per_unit_material = row[:qty].positive? ? (row[:material] / row[:qty]).round : 0
    per_unit_material + row[:process] + row[:overhead]
  end

  def summary_rows
    rows = [title_row('生产任务单成本', SUMMARY_HEADERS.size),
            SUMMARY_HEADERS.map { |h| [h, :s, :header] }]
    costed.each { |row| rows << summary_row(row) }
    rows << summary_total
    rows
  end

  def summary_row(row)
    bom = row[:order].bom
    [[row[:order].order_no, :s, :center],
     [bom.submit_date&.to_s, :s, :center],
     [bom.model.presence || bom.crm_product&.name, :s, :text],
     [row[:qty].to_f, :n, :center],
     [bom.unit, :s, :center],
     money(row[:material]), money(row[:process]), money(row[:overhead]),
     money(unit_cost(row)),
     [row[:unpriced], :n, :center],
     [row[:unpriced].positive? ? "#{row[:unpriced]} 行无单价，成本为不完全值" : '', :s, :text]]
  end

  def summary_total
    row = Array.new(SUMMARY_HEADERS.size) { ['', :s, :subtotal_text] }
    row[0] = ['总计', :s, :subtotal_text]
    row[5] = [micros_to_f(costed.sum { |c| c[:material] }), :n, :subtotal_money]
    row[9] = [costed.sum { |c| c[:unpriced] }, :n, :subtotal_text]
    row
  end

  def detail_rows
    rows = [title_row('用料明细（含单价）', DETAIL_HEADERS.size),
            DETAIL_HEADERS.map { |h| [h, :s, :header] }]
    costed.each do |row|
      row[:items].each_with_index { |item, i| rows << detail_row(row, item, i + 1) }
    end
    rows
  end

  def detail_row(row, item, seq)
    price = row[:prices][item.id]
    [[row[:order].order_no, :s, :center],
     [seq, :n, :center],
     [item.material_no, :s, :center],
     [item.material_name, :s, :text],
     [item.specification, :s, :text],
     [item.unit, :s, :center],
     [item.qty.to_f, :n, :center],
     price ? money(price[:price_micros]) : ['', :s, :center],
     price ? money((item.qty.to_d * price[:price_micros]).round) : ['', :s, :center],
     [price ? price[:source_label] : '无单价', :s, :center]]
  end

  def title_row(text, width)
    label = [text, @label.presence].compact.join(' · ')
    [[label, :s, :title]] + Array.new(width - 1) { ['', :s, :title] }
  end

  def money(micros) = [micros_to_f(micros), :n, :money]
  def micros_to_f(micros) = (micros.to_i / 1_000_000.0).round(4)
end
