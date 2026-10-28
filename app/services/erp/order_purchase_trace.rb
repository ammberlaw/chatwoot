# 一张销售订单背后的采购：买了什么、跟谁买、花了多少。
#
# ⚠️ 为什么不加进 Crm::SalesOrderTraceService：那个服务 **CRM 销售端也在用**
# （订单页的 production_trace 接口），里面明确写着「单价、供应商不进这里——销售端不可见成本」。
# 把采购金额塞进去，业务员在自己的订单页就能看到采购价和供应商了。
# 所以单开一个只给 ERP 调的服务，天然不会漏到销售那边。
#
# 两个口径一起给（用户点名要两种）：
#   ① 关联该生产订单的采购单——实际为这单下的采购，带供应商和金额
#   ② 每颗料最近一次的采购单价——不一定来自本单，用于判断这次买贵了还是便宜了
#
# ⚠️ 合并采购：一张采购单可以挂多张生产订单（extra_production_order_ids），
# 这种单的金额**不全属于这张销售订单**，必须标出来，否则财务会把别单的钱算进本单成本。
class Erp::OrderPurchaseTrace
  def initialize(account:, sales_order:)
    @account = account
    @sales_order = sales_order
  end

  def call
    po_ids = production_order_ids
    return { purchase_orders: [], last_prices: [] } if po_ids.empty?

    orders = purchase_orders(po_ids)
    { purchase_orders: orders.map { |po| order_json(po, po_ids) },
      last_prices: last_prices(orders) }
  end

  private

  def production_order_ids
    @account.mes_production_orders.where(crm_sales_order_id: @sales_order.id).pluck(:id)
  end

  # 本单的采购单 = 直接挂在这些生产订单上的 + 通过合并采购带上的。
  def purchase_orders(po_ids)
    @account.mes_purchase_orders
            .where('production_order_id IN (:ids) OR extra_production_order_ids && ARRAY[:ids]::bigint[]', ids: po_ids)
            .includes(purchase_items: [:mes_supplier, :mes_material, :crm_product])
            .order(:created_at)
  end

  def order_json(order, po_ids)
    all = ([order.production_order_id] + Array(order.extra_production_order_ids)).compact.uniq
    { id: order.id, po_no: order.po_no, status: order.status, approval_status: order.approval_status,
      total_amount_micros: order.total_amount_micros,
      suppliers: order.purchase_items.filter_map { |i| i.mes_supplier&.name }.uniq,
      ordered_at: order.created_at,
      # 这张单还给别的生产订单买了料，金额不能整个算到本单头上。
      shared_with_others: (all - po_ids).any?,
      items: order.purchase_items.map { |i| item_json(i) } }
  end

  def item_json(item)
    { name: item.mes_material&.name || item.crm_product&.name,
      code: item.mes_material&.material_no || item.crm_product&.sku,
      qty: item.qty.to_f, unit: item.unit,
      rate_micros: item.rate_micros, amount_micros: item.amount_micros,
      price_tax_included: item.price_tax_included,
      supplier_name: item.mes_supplier&.name }
  end

  # 每颗料「最近一次采购单价」。复用 Mes::LastPurchasePrice——它只认审批通过的单，
  # 口径与成本归集那边的最近采购价一致，另写一套迟早对不上。
  # 排除本单自己（exclude_po_id），否则查出来的就是这次的价，比不出涨跌。
  def last_prices(orders)
    seen = {}
    orders.each do |po|
      po.purchase_items.each do |item|
        key = [item.mes_material_id, item.crm_product_id]
        next if seen.key?(key)

        last = Mes::LastPurchasePrice.for(
          account: @account, crm_product_id: item.crm_product_id,
          mes_material_id: item.mes_material_id, exclude_po_id: po.id
        )
        # 查不到上次价的也要返回（rate_micros 为 nil），界面上标「首次采购」。
        # 只返回有历史价的那几颗，会让人以为别的料没采购过——实际是它们第一次买。
        seen[key] = {
          name: item.mes_material&.name || item.crm_product&.name,
          code: item.mes_material&.material_no || item.crm_product&.sku,
          this_rate_micros: item.rate_micros
        }.merge(last || {})
      end
    end
    seen.values
  end
end
