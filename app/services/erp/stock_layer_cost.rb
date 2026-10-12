# 建一层存货时，这一层按多少钱入账。
#
# 口径与 CostRollupService 的「自产按领料、外协按采购」是同一套，二选一互不重叠：
#   采购收货（成品/原料）→ 这张采购单那一行的金额 ÷ 数量。**这是原料 FIFO 的命根子**：
#                           每批货带着它自己进货时的价，后面领料才扣得对。
#   自产完工入库         → 该生产订单归集成本 ÷ 完工数量。
# 取不到价的按 0 建层——宁可少算也不编数，存货页上看得见缺口、财务可手工补。
class Erp::StockLayerCost
  PRODUCT = 'PRODUCT'.freeze

  def initialize(account)
    @account = account
  end

  def for(entry, item, qty)
    micros = case entry.purpose
             when 'MATERIAL_RECEIPT' then purchase_unit_cost(entry, item)
             when 'MANUFACTURE' then manufacture_unit_cost(entry, qty)
             else 0
             end
    [micros.to_i, 0].max
  end

  private

  def purchase_unit_cost(entry, item)
    line = purchase_line_for(entry, item)
    return 0 if line.nil? || line.amount_micros.blank? || line.qty.to_d <= 0

    (line.amount_micros / line.qty.to_d).round
  end

  # 这张入库单对应的采购行。成品按商品档对；原料优先按物料档对，没有物料 id 才按商品档
  # ——同一颗料两种挂法都有，只认一种会让大半原料建成 0 成本的层。
  def purchase_line_for(entry, item)
    lines = entry.purchase_order&.purchase_items || []
    lines.find(&match_for(item))
  end

  def match_for(item)
    return ->(line) { line.item_type == PRODUCT && line.crm_product_id == item.crm_product_id } if item.item_type == PRODUCT
    return ->(line) { line.mes_material_id == item.mes_material_id } if item.mes_material_id.present?

    ->(line) { line.crm_product_id.present? && line.crm_product_id == item.crm_product_id }
  end

  def manufacture_unit_cost(entry, qty)
    order = entry.production_order
    return 0 if order.blank? || qty <= 0

    total = Erp::CostRollupService.new(@account).production_cost_micros(order)
    return 0 if total.to_i <= 0

    (total / qty).round
  end
end
