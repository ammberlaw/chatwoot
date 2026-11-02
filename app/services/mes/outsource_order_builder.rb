# 从生产订单开委外加工单（用户 2026-10-31 定：委外加工单从生产订单转）。
#
# 为什么要从生产订单转、而不是独立开单：销售订单→生产订单→委外加工→产品入库→发货
# 要连成一条链，业务端查进度才看得到「在 XX 厂加工中」。独立开单这一段就断了。
#
# 用料从这张订单的生产任务单（BOM）带过来：分子＝BOM 单位用量，分母＝BOM 基准产量，
# 和金蝶的「材料用量(分子) / 产品产量(分母)」是同一个口径。损耗率默认 0，谈好了再改。
class Mes::OutsourceOrderBuilder
  class Error < StandardError; end

  def initialize(account:, actor: nil)
    @account = account
    @actor = actor
  end

  def from_production_order(production_order, attrs = {})
    attrs = attrs.symbolize_keys
    ensure_buildable!(production_order)
    # 加工厂是开单时就要选的——先建单再补会出现「料发给谁」说不清的草稿。
    # 这里挡一道，不然只能看到 belongs_to 的英文校验信息。
    raise Error, '开委外加工单要先选加工厂' if attrs[:mes_supplier_id].blank?

    order = @account.mes_outsource_orders.new(default_attrs(production_order).merge(attrs))
    order.save!
    copy_bom_materials(order, production_order)
    order.outsource_materials.reload.each(&:recompute_std_qty!)
    order
  end

  private

  def ensure_buildable!(production_order)
    raise Error, '这张生产订单没有产品，开不了委外加工单' if production_order.crm_product_id.blank?

    open = @account.mes_outsource_orders.open_orders.where(production_order_id: production_order.id)
    return if open.empty?

    raise Error, "这张生产订单已经有委外加工单 #{open.first.order_no} 了，别重复开"
  end

  def default_attrs(production_order)
    { production_order_id: production_order.id,
      crm_product_id: production_order.crm_product_id,
      qty: production_order.qty,
      unit: production_order.unit,
      product_line: production_order.product_line,
      doc_date: Date.current,
      delivery_date: production_order.planned_end_date&.to_date,
      owner_id: @actor&.id,
      status: 'DRAFT' }
  end

  # 用料行照搬 BOM。BOM 没挂（外购短脊柱的单常常没有）就建空单，让人自己加料。
  # 发料仓默认原料仓：不给默认值的话发料单上每行都没仓库，过账时查到的是
  # 「仓库为空」的结存＝0，报一串「库存不足」，而料其实在原料仓好好躺着。
  def copy_bom_materials(order, production_order)
    bom = production_order.bom
    return if bom.nil?

    base = bom.base_qty.to_d.zero? ? 1 : bom.base_qty.to_d
    raw_id = default_raw_warehouse_id
    bom.bom_items.each do |item|
      order.outsource_materials.create!(
        account_id: @account.id, mes_material_id: item.mes_material_id, unit: item.unit,
        qty_numerator: item.qty, qty_denominator: base, loss_rate: 0,
        from_warehouse_id: raw_id
      )
    end
  end

  def default_raw_warehouse_id
    @account.mes_warehouses.where(kind: 'RAW').order(:id).pick(:id)
  end
end
