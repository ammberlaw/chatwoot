# 扫描一个账号的 MES 预警：逾期 / 临近交期 / 阶段滞留 / 短缺物料。
# 看板与每日预警推送共用。
class Mes::AlertScannerService
  STALL_DAYS = 3
  DUE_SOON_DAYS = 3

  def initialize(account, product_line: nil, owner_ids: :all)
    @account = account
    @product_line = product_line.presence
    @owner_ids = owner_ids
  end

  def call
    open_orders = @account.mes_production_orders.published
                          .where.not(status: 'CANCELLED').where.not(stage: 'SHIPPED')
                          .includes(:stage_events, :purchase_orders)
    open_orders = open_orders.where(product_line: @product_line) if @product_line
    open_orders = open_orders.where(owner_id: @owner_ids) unless @owner_ids == :all
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
      # 未接单超时（装死）：进入阶段过了接单时限仍没人接单。小时数按工作时间累计（跳周末/下班）。
      unacked << row.merge(hours: worked_hours_since(po.stage_entered_at, now), owner_names: po.current_stage_owner_names) if po.ack_overdue?

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

  # 两时刻间的工作小时数（工作日 08:00–17:30、跳周末），向下取整。
  def worked_hours_since(from, to)
    (WorkingHours.working_time_between(from, to) / 1.hour).floor
  end

  def order_row(po)
    { id: po.id, order_no: po.order_no, product_name: po.product_name, stage: po.stage, delivery_date: po.delivery_date,
      purchase_state: purchase_state(po), purchase_warn: purchase_warn?(po) }
  end

  # 采购推进到哪了。PMC 看到逾期单第一个问题就是「采购到底下了没」,
  # 光写阶段看不出来,得挨个点进去查——所以直接写进预警行。
  # 已取消的采购单不算数（等于没下）。
  def live_purchase_orders(order)
    order.purchase_orders.reject { |po| po.status == 'CANCELLED' }
  end

  # 判定顺序即优先级：先看到没到货,再看有没有停在草稿。
  PURCHASE_STATES = [
    ['采购单已到货', ->(pos) { pos.all? { |po| po.status == 'RECEIVED' } }],
    ['采购单部分到货', ->(pos) { pos.any? { |po| po.status == 'PARTIAL_RECEIVED' } }],
    ['采购单还是草稿', ->(pos) { pos.all? { |po| po.status == 'DRAFT' } }]
  ].freeze

  def purchase_state(order)
    pos = live_purchase_orders(order)
    return '未下采购单' if pos.empty?

    hit = PURCHASE_STATES.find { |_label, cond| cond.call(pos) }
    hit ? hit.first : '采购单已提交'
  end

  # 需要有人立刻去动的两种：压根没下单,或者下了但停在草稿没提交。
  def purchase_warn?(order)
    pos = live_purchase_orders(order)
    pos.empty? || pos.all? { |po| po.status == 'DRAFT' }
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
