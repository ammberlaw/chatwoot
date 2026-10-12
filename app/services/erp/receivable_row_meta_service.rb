# 应收台账列表按财务旧系统（金蝶）「销售出库明细」的口径出列，多出来的几列不在应收表上：
# 单据日期/单据编号/仓库在出库单，单位/事业部在商品档，部门在组织架构。
# 三样都批量取——一页 50 笔逐条问一遍就是上百条查询，列表直接卡住。
class Erp::ReceivableRowMetaService
  def initialize(account:, receivables:)
    @account = account
    @receivables = receivables
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
    skus = @receivables.flat_map { |r| r.crm_sales_order&.line_item_rows.to_a.pluck(:sku) }
                       .compact_blank.uniq
    return {} if skus.empty?

    @account.crm_products.where(sku: skus)
            .pluck(:sku, :unit, :product_line)
            .to_h { |sku, unit, line| [sku, { unit: unit, product_line: line }] }
  end

  # 业务员的归属部门（is_primary）。没设归属就退而取他所在的任一部门。
  def departments
    owner_ids = @receivables.filter_map(&:owner_id).uniq
    return {} if owner_ids.empty?

    Org::Membership.where(account_id: @account.id, user_id: owner_ids)
                   .includes(:department).order(is_primary: :desc)
                   .each_with_object({}) { |m, acc| acc[m.user_id] ||= m.department&.name }
  end

  private

  def order_ids
    @order_ids ||= @receivables.filter_map(&:crm_sales_order_id).uniq
  end
end
