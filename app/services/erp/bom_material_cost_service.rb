# 按 BOM 把「单台材料成本」算出来，给 ERP 的 BOM 成本表用。
#
# 为什么要算：BOM 成本表的材料成本栏原来只有人工填/Excel 导入两条路，生产上 179 个编码
# 里只有 29 个有数，而那 29 个恰恰一个 BOM 都没做过——有 BOM 的 23 个反而是 0。
# 两套数据各走各的，表上看不出「这个产品到底有没有成本」。
#
# 料价不在 BOM 行上存（mes_bom_items.rate_micros 生产上 1223 行全是 0，生产任务单的
# 物料清单根本没有录价的入口）。所以价从 Mes::MaterialPriceResolver 现查：
#   标准价（物料单价表）→ 最近采购价，**不传 production_orders**——
#   这张表是产品级标准成本，绑某张订单的采购价会让同一个编码随订单变。
#
# 口径与 Mes::BomCostXlsxService 一致：
#   整单材料 = Σ(用量 × 单价)，单台材料 = 整单材料 ÷ 基准用量 base_qty
#   查不到价的行记 0 并计入 unpriced_count——覆盖率不可能 100%，
#   一个不标缺口的合计会被当成完整成本用。
class Erp::BomMaterialCostService
  Result = Struct.new(:bom, :items, :total_micros, :unit_micros,
                      :unpriced_count, keyword_init: true) do
    def item_count = items.size
  end

  def initialize(account, product_ids)
    @account = account
    @product_ids = Array(product_ids).compact.uniq
  end

  # => { crm_product_id => Result }，没做过 BOM 的产品不出现在结果里
  def perform
    return {} if @product_ids.empty? || boms.empty?

    boms.to_h { |bom| [bom.crm_product_id, result_for(bom)] }
  end

  # 一行物料的金额（micros）。查不到价记 0——宁可少算不编数。
  def priced_amount(item)
    price = prices[item.id]
    price ? (item.qty.to_d * price[:price_micros]).round : 0
  end

  # 行上的单价与价源，给展开明细直接用。
  def price_for(item) = prices[item.id]

  private

  # 单台材料成本 = Σ(用量 × 单价) ÷ 基准用量。基准用量理论上恒 > 0（模型有校验），
  # 真遇到 0 就按整单值记，不是除零崩掉。
  def result_for(bom)
    items = items_by_bom[bom.id] || []
    total = items.sum { |i| priced_amount(i) }
    base = bom.base_qty.to_d
    Result.new(bom: bom, items: items, total_micros: total,
               unit_micros: base.positive? ? (total / base).round : total,
               unpriced_count: items.count { |i| prices[i.id].nil? })
  end

  # 每个产品取一张 BOM：默认 BOM 优先，否则最近做的那张。
  # 口径和 BomCostsController#materials 原来的 order(is_default: :desc, id: :desc).first 一致，
  # 只是改成一次查完——一页 25 行各查一次就是 25 条 SQL。
  def boms
    @boms ||= @account.mes_boms
                      .where(crm_product_id: @product_ids)
                      .select('DISTINCT ON (crm_product_id) mes_boms.*')
                      .order('crm_product_id, is_default DESC, id DESC')
                      .to_a
  end

  def items_by_bom
    @items_by_bom ||= @account.mes_bom_items.where(bom_id: boms.map(&:id)).order(:id).group_by(&:bom_id)
  end

  # 一次给所有 BOM 的所有物料配价：resolver 内部的物料档/采购价目录按账户缓存一次，
  # 分开实例化等于每张 BOM 重扫一遍采购明细。
  def prices
    @prices ||= Mes::MaterialPriceResolver.new(account: @account, items: items_by_bom.values.flatten).perform
  end
end
