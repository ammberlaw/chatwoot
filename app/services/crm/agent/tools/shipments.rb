# 出货情况：发了没、发了哪些货各多少、从哪个仓发的、审批走到哪一步。
#
# order_progress 只给出一个出货单号和日期，客户追问「发了几台、什么时候发的」
# 还得人自己去 MES 翻单。
#
# 权限跟着**客户**走而不是 owner_id：出货单的 owner 常常是仓管或 MES 那边的人，
# 按 owner 过滤，业务员一张自己客户的出货都看不到（口径见 Scope#shipments）。
#
# ⚠️ 只给数量、日期、仓库。供应商、采购价、成本一个字都不给——销售端不可见。
class Crm::Agent::Tools::Shipments < Crm::Agent::Tools::Base
  description '查出货单：某张销售订单或某个客户发货了没、发了哪些产品各多少、出货日期、审批到哪一步、从哪个仓发的。'
  param :order_no, desc: '销售订单号，查这张单的出货', required: false
  param :customer_id, type: 'integer', desc: '客户ID，列这个客户最近的出货', required: false
  param :shipment_no, desc: '出货单号（DN- 开头）', required: false
  param :limit, type: 'integer', desc: '最多列几张，默认 8，上限 20', required: false

  STATUSES = { 'DRAFT' => '草稿', 'PENDING_APPROVAL' => '待审核', 'APPROVED' => '已审核待发',
               'REJECTED' => '已驳回', 'SHIPPED' => '已出货', 'CANCELLED' => '已取消' }.freeze
  KINDS = { 'PRODUCTION' => '生产出货', 'STOCK' => '现货出库' }.freeze

  def execute(order_no: nil, customer_id: nil, shipment_no: nil, limit: 8)
    rows = pick(order_no, customer_id, shipment_no, limit.to_i.positive? ? [limit.to_i, 20].min : 8)
    return '请给销售订单号、客户ID 或出货单号。' if rows.nil?
    return '没找到你能看到的出货单（可能还没安排出货）。' if rows.empty?

    "【出货单】共 #{rows.size} 张：\n#{rows.map { |s| render(s) }.join("\n\n")}"
  end

  private

  def pick(order_no, customer_id, shipment_no, limit)
    base = scope.shipments.includes(:crm_customer, :crm_sales_order, :warehouse, shipment_items: :crm_product)
    if shipment_no.present?
      base.where('shipment_no ILIKE ?', "%#{shipment_no.to_s.strip}%").limit(limit).to_a
    elsif order_no.present?
      base.joins(:crm_sales_order).where('crm_sales_orders.order_no ILIKE ?', "%#{order_no.to_s.strip}%")
          .order(id: :desc).limit(limit).to_a
    elsif customer_id.present?
      base.where(crm_customer_id: customer_id.to_i).order(id: :desc).limit(limit).to_a
    end
  end

  def render(shipment)
    "— #{shipment.shipment_no}｜#{KINDS[shipment.kind] || shipment.kind}｜" \
      "#{STATUSES[shipment.status] || shipment.status}｜#{belongs(shipment)}｜" \
      "#{shipped_label(shipment)}｜仓库 #{shipment.warehouse&.name || '—'}#{items_block(shipment)}"
  end

  def belongs(shipment)
    "客户 #{shipment.crm_customer&.name || '—'}｜订单 #{shipment.crm_sales_order&.order_no || '—'}"
  end

  # 「已发」只认 SHIPPED 状态：审批中、待发的单也可能先填了计划出货日，
  # 照着那个日期回客户「货已经发了」就是事故。
  def shipped_label(shipment)
    return "已发 #{day(shipment.shipped_at)}" if shipment.status == 'SHIPPED'
    return "还没发（计划 #{day(shipment.shipped_at)}）" if shipment.shipped_at.present?

    '还没发出'
  end

  def items_block(shipment)
    rows = shipment.shipment_items.map { |i| item_line(i) }
    rows.empty? ? '' : "\n  #{rows.join("\n  ")}"
  end

  def item_line(item)
    product = item.crm_product
    "#{product&.sku || '—'} #{product&.name || '（产品已删）'} × #{fnum(item.qty)}#{item.unit.presence || product&.unit}"
  end
end
