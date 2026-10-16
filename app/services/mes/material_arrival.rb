# 这张生产订单的「物料到货明细」：一屏列全，整机料和包装料都在。
#
# 用户原话：「这1个工单原材料入库查找起来比较麻烦，都是一个一个的找……
# 1个工单应该包含这个单所有的物料明细，无论是组装还是包装物料都方便查找」。
# 生产上一张工单的料会摊成十几张入库单（一家供应商一张），要逐张点开才数得清到了多少。
#
# 和另外两个齐套视图的分工（三者必须同口径，否则会出现「徽标说差、清单说齐」）：
#   Mes::KitReadiness —— 齐没齐，给列表上那两枚徽标
#   Mes::KitShortage  —— 还差什么，按采购单分组，只列缺的
#   本服务            —— 全量明细：每颗料需求多少、下了多少、到了多少、挂在哪几张采购单
#
# 口径：需求量 = BOM 行用量 × 订单量/基准量；下单/到货量按**产品档案**归集，
# 关闭的采购单不算（它的货不会来了）。实时库存那列对齐金蝶领料单上的「即时库存」。
class Mes::MaterialArrival
  CATEGORY_LABELS = { 'MACHINE' => '整机物料', 'PACKAGING' => '包装物料' }.freeze

  def self.for(order) = new(order).call

  def initialize(order)
    @order = order
  end

  # [{ category:, category_label:, material_no:, name:, specification:, unit:,
  #    required:, ordered:, received:, outstanding:, on_hand:, po_nos: [] }]
  # 没挂 BOM / 基准量为 0 → 空数组（料还没定出来，没什么可列的）。
  def call
    return [] if rows.empty? || factor.zero?

    rows.map { |item| row_for(item) }
  end

  private

  def rows = @rows ||= @order.bom&.bom_items.to_a

  def factor
    @factor ||= begin
      base = @order.bom&.base_qty.to_d
      base.zero? ? 0 : @order.qty.to_d / base
    end
  end

  def row_for(item)
    pid = product_ids[item.material_no]
    describe(item).merge(quantities(item, pid))
  end

  # 这颗料「是什么」——照搬 BOM 行，不去产品档案另取一份（两处对不上更难查）。
  def describe(item)
    {
      category: item.category,
      category_label: CATEGORY_LABELS[item.category] || item.category,
      material_no: item.material_no,
      name: item.material_name,
      specification: item.specification,
      aux_attribute_name: item.aux_attribute_name,
      unit: item.unit
    }
  end

  # 这颗料「走到哪了」——需求 / 下单 / 到货 / 还差 / 实时库存 / 挂在哪几张采购单。
  def quantities(item, pid)
    required = item.qty.to_d * factor
    stat = purchase_stats[pid] || {}
    received = stat[:received].to_d
    {
      required: required, ordered: stat[:ordered].to_d, received: received,
      # 还差多少到货。超收不显示负数。
      outstanding: [required - received, 0].max,
      on_hand: on_hand[pid].to_d, po_nos: stat[:po_nos].to_a
    }
  end

  def product_ids
    @product_ids ||= begin
      codes = rows.filter_map(&:material_no).uniq
      codes.empty? ? {} : Crm::Product.where(account_id: @order.account_id, sku: codes).pluck(:sku, :id).to_h
    end
  end

  # { crm_product_id => { ordered:, received:, po_nos: [] } }
  def purchase_stats
    @purchase_stats ||= Mes::PurchaseItem
                        .joins(:purchase_order)
                        .where(mes_purchase_orders: { production_order_id: @order.id })
                        .where.not(mes_purchase_orders: { status: 'CANCELLED' })
                        .where.not(crm_product_id: nil)
                        .pluck(:crm_product_id, :qty, :received_qty, 'mes_purchase_orders.po_no')
                        .each_with_object({}) { |(pid, qty, got, po_no), acc| merge_stat(acc, pid, qty, got, po_no) }
  end

  def merge_stat(acc, pid, qty, got, po_no)
    row = (acc[pid] ||= { ordered: 0.to_d, received: 0.to_d, po_nos: [] })
    row[:ordered] += qty.to_d
    row[:received] += got.to_d
    row[:po_nos] |= [po_no]
  end

  def on_hand = @on_hand ||= compute_on_hand

  def compute_on_hand
    ids = product_ids.values
    return {} if ids.empty?

    Mes::StockBalance.where(account_id: @order.account_id, crm_product_id: ids)
                     .group(:crm_product_id).sum(:qty)
  end
end
