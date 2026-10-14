# 这颗料被**别的在产订单**排掉了多少（BOM 上的需求量 − 已领的量）。
#
# 用户原话：「新建生产任务单选择物料编码时，系统的实时库存要提示是否有其他已下订单
# 占用库存，比如你可以在实时库存的库存边上加一个感叹号悬停跳出提示」。
# 实时库存写着 100 不代表这 100 能用——别的单早排上了，工程照着这个数决定不采购，
# 到领料那天就缺货。
#
# 口径：在产（IN_PROGRESS、已生效、未出货）且挂了生产任务单的订单，
#   需求 = BOM 行用量 ÷ BOM 基准量 × 订单数量
#   已领 = 这张订单已过账的领料单里这颗料的数量
#   占用 = max(需求 − 已领, 0)
# 领料明细挂的是产品档案（crm_product_id），BOM 行上只有料号，按料号＝SKU 对上。
class Mes::MaterialCommitment
  ISSUE_PURPOSE = 'MATERIAL_ISSUE'.freeze

  def self.by_material_no(account, exclude_bom_id: nil)
    new(account, exclude_bom_id: exclude_bom_id).by_material_no
  end

  def initialize(account, exclude_bom_id: nil)
    @account = account
    @exclude_bom_id = exclude_bom_id
  end

  # { 料号 => 被别的单占用的数量 }，没被占用的料不出现在结果里。
  def by_material_no
    return {} if orders.empty?

    totals = orders.each_with_object(Hash.new(0.to_d)) do |order, acc|
      base = order.bom.base_qty.to_d
      next if base.zero?

      order.bom.bom_items.each { |item| accumulate(acc, order, item, base) }
    end
    totals.select { |_no, qty| qty.positive? }
  end

  private

  def accumulate(acc, order, item, base)
    return if item.material_no.blank?

    need = item.qty.to_d / base * order.qty.to_d
    left = need - issued_qty(order.id, item.material_no)
    acc[item.material_no] += left if left.positive?
  end

  def orders
    @orders ||= begin
      scope = @account.mes_production_orders.published
                      .where(status: 'IN_PROGRESS').where.not(stage: 'SHIPPED')
                      .where.not(bom_id: nil)
      scope = scope.where.not(bom_id: @exclude_bom_id) if @exclude_bom_id.present?
      scope.includes(bom: :bom_items).to_a
    end
  end

  def issued_qty(order_id, material_no)
    pid = product_id_by_sku[material_no]
    pid ? issued[[order_id, pid]].to_d : 0.to_d
  end

  def product_id_by_sku
    @product_id_by_sku ||= begin
      codes = orders.flat_map { |o| o.bom.bom_items.map(&:material_no) }.compact_blank.uniq
      codes.empty? ? {} : @account.crm_products.where(sku: codes).pluck(:sku, :id).to_h
    end
  end

  # { [订单id, 产品id] => 已领数量 }，只认已过账的领料单。
  def issued
    @issued ||= Mes::StockEntryItem
                .joins(:stock_entry)
                .where(mes_stock_entries: { account_id: @account.id, purpose: ISSUE_PURPOSE,
                                            status: 'POSTED', production_order_id: orders.map(&:id) })
                .where.not(crm_product_id: nil)
                .group('mes_stock_entries.production_order_id', 'mes_stock_entry_items.crm_product_id')
                .sum(:qty)
  end
end
