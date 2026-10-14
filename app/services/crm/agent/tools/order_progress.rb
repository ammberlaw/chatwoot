# 「我这张单做到哪了」——订单在车间走到哪个阶段、货出了没有。
#
# 业务员被客户追交期时问的就是这句，以前得自己点进 MES 的看板翻。
#
# ⚠️ 只露**阶段名**和出货日期。供应商、采购价、成本、毛利一个字都不给——
# 这些字段在生产单和订单上都有，但销售端不可见是公司硬规定，
# 而 agent 的回答会原样摆在业务员眼前。
class Crm::Agent::Tools::OrderProgress < Crm::Agent::Tools::Base
  description '查销售订单的生产进度与出货情况：走到哪个生产阶段、计划交期、已出货的单号和日期。可以按订单号查一张，也可以给客户ID列这个客户在产的单。'
  param :order_no, desc: '销售订单号，查单张时给', required: false
  param :customer_id, type: 'integer', desc: '客户ID，列这个客户的在产订单时给', required: false

  def execute(order_no: nil, customer_id: nil)
    orders = pick(order_no, customer_id)
    return '请给订单号或客户ID。' if orders.nil?
    return '没找到你能看到的对应订单。' if orders.empty?

    orders.map { |order| render(order) }.join("\n\n")
  end

  private

  def pick(order_no, customer_id)
    if order_no.present?
      scope.sales_orders.where('order_no ILIKE ?', "%#{order_no.to_s.strip}%").limit(5).to_a
    elsif customer_id.present?
      scope.sales_orders.where(crm_customer_id: customer_id.to_i)
           .order(order_date: :desc, id: :desc).limit(8).to_a
    end
  end

  def render(order)
    head = "【#{order.order_no}】#{order.crm_customer&.name || '客户未挂'}｜下单 #{day(order.order_date)}｜" \
           "#{money(order.order_amount_micros, order.order_currency.presence || 'CNY')}｜" \
           "订单状态 #{Crm::SalesOrder::STATUS_LABELS[order.status] || order.status}｜交期 #{day(order.delivery_date)}"
    [head, mes_lines(order), shipment_line(order)].compact_blank.join("\n")
  end

  # 一张销售订单可能拆成好几张生产单（不同产品各一张），逐张报阶段。
  def mes_lines(order)
    rows = scope.account.mes_production_orders.where(crm_sales_order_id: order.id).order(:id)
    return '生产：还没有开生产单。' if rows.empty?

    rows.map do |po|
      "生产 #{po.order_no}｜#{po.product_name}×#{fnum(po.qty)}｜" \
        "当前阶段 #{Mes::ProductionOrder::STAGE_LABELS[po.stage] || po.stage}｜" \
        "已完工 #{fnum(po.produced_qty)}｜计划完工 #{day(po.planned_end_date)}｜#{status_text(po)}"
    end.join("\n")
  end

  STATUS_TEXTS = { 'IN_PROGRESS' => '在产', 'COMPLETED' => '已完成', 'STOPPED' => '已暂停', 'CANCELLED' => '已取消' }.freeze

  def status_text(production_order)
    STATUS_TEXTS[production_order.status] || production_order.status
  end

  def shipment_line(order)
    rows = scope.account.mes_shipments.where(crm_sales_order_id: order.id).where.not(shipped_at: nil).order(:shipped_at)
    return '出货：还没有出货记录。' if rows.empty?

    "出货：#{rows.map { |s| "#{s.shipment_no}（#{day(s.shipped_at)}）" }.join('、')}"
  end
end
