# 扫描一个账号的 MES 预警：逾期 / 临近交期 / 阶段滞留 / 短缺物料。
# 看板与每日预警推送共用。
class Mes::AlertScannerService
  STALL_DAYS = 3
  DUE_SOON_DAYS = 3

  def initialize(account, product_line: nil)
    @account = account
    @product_line = product_line.presence
  end

  def call
    open_orders = @account.mes_production_orders.published
                          .where.not(status: 'CANCELLED').where.not(stage: 'SHIPPED')
                          .includes(:stage_events)
    open_orders = open_orders.where(product_line: @product_line) if @product_line
    overdue, due_soon, stalled, unacked = classify(open_orders)
    { overdue: overdue, due_soon: due_soon, stalled: stalled, unacked: unacked, shortages: shortages }
  end

  private

  def classify(orders)
    now = Time.current
    overdue = []
    due_soon = []
    stalled = []
    unacked = []
    orders.each do |po|
      row = order_row(po)
      if po.delivery_date.present? && po.delivery_date < now
        overdue << row.merge(days: ((now - po.delivery_date) / 1.day).ceil)
      elsif po.delivery_date.present? && po.delivery_date <= now + DUE_SOON_DAYS.days
        due_soon << row.merge(days: ((po.delivery_date - now) / 1.day).ceil)
      end
      # 未接单超时（装死）：进入阶段过了接单时限仍没人接单。
      unacked << row.merge(hours: ((now - po.stage_entered_at) / 1.hour).floor, owner_names: po.current_stage_owner_names) if po.ack_overdue?

      ev = po.stage_events.find { |e| e.stage == po.stage }
      next unless ev

      days = ((now - ev.entered_at) / 1.day).floor
      stalled << row.merge(days: days) if days >= STALL_DAYS
    end
    [
      overdue.sort_by { |r| -r[:days] },
      due_soon.sort_by { |r| r[:days] },
      stalled.sort_by { |r| -r[:days] },
      unacked.sort_by { |r| -r[:hours] }
    ]
  end

  def order_row(po)
    { id: po.id, order_no: po.order_no, product_name: po.product_name, stage: po.stage, delivery_date: po.delivery_date }
  end

  def shortages
    scope = @account.mes_stock_balances.includes(:mes_material, :warehouse).where('qty <> 0')
    scope = scope.where(product_line: @product_line) if @product_line
    scope.select(&:short?)
            .map do |b|
      { material_name: b.mes_material&.name, warehouse_name: b.warehouse&.name, qty: b.qty, safety_stock: b.mes_material&.safety_stock }
    end
  end
end
