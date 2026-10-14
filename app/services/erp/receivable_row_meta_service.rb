# 应收台账列表按财务旧系统（金蝶）「销售出库明细」的口径出列，多出来的几列不在应收表上：
# 单据日期/单据编号/仓库在出库单，单位/事业部在商品档，部门在组织架构。
# 三样都批量取——一页 50 笔逐条问一遍就是上百条查询，列表直接卡住。
#
# 待建账那一页要的是同一套列（用户点名「待建账的表头要和应收台账一样」），只是还没有台账，
# 所以两种入口都收：给 receivables 走订单关联，给 orders 直接用。
class Erp::ReceivableRowMetaService
  def initialize(account:, receivables: nil, orders: nil)
    @account = account
    @orders = Array(orders).presence || Array(receivables).filter_map(&:crm_sales_order)
    # 部门按「这一行上的业务员」取：台账行认台账的 owner，待建账行认订单的 owner，
    # 两者可能不是同一个人（台账建好后改派过）。
    @owner_ids = (Array(orders).presence || Array(receivables)).filter_map(&:owner_id).uniq
  end

  # 取这张订单**首次出库**的那张出库单：一张订单分批出货时金蝶是一张出库单一行，
  # 我们台账一笔一行，取首次＝账期起算那次。
  def shipments
    return {} if order_ids.empty?

    @account.mes_shipments
            .where(crm_sales_order_id: order_ids).where.not(shipped_at: nil)
            .includes(:warehouse).order(shipped_at: :asc)
            .each_with_object({}) do |shipment, acc|
              # order(asc) + 只认第一次写入 ＝ 每张订单留最早那张。
              acc[shipment.crm_sales_order_id] ||= {
                shipped_on: shipment.shipped_at&.to_date,
                shipment_no: shipment.shipment_no,
                warehouse_name: shipment.warehouse&.name
              }
            end
  end

  # 订单明细是 jsonb 快照、只存了 sku，单位和产线在商品档上。
  # sku 可能对不上任何在档商品（手打的、已删的），取不到就留空。
  def products
    skus = @orders.flat_map { |o| o.line_item_rows.to_a.pluck(:sku) }.compact_blank.uniq
    return {} if skus.empty?

    @account.crm_products.where(sku: skus)
            .pluck(:sku, :unit, :product_line)
            .to_h { |sku, unit, line| [sku, { unit: unit, product_line: line }] }
  end

  # 业务员的归属部门（is_primary）。没设归属就退而取他所在的任一部门。
  def departments
    return {} if @owner_ids.empty?

    Org::Membership.where(account_id: @account.id, user_id: @owner_ids)
                   .includes(:department).order(is_primary: :desc)
                   .each_with_object({}) { |m, acc| acc[m.user_id] ||= m.department&.name }
  end

  private

  def order_ids
    @order_ids ||= @orders.map(&:id).uniq
  end
end
