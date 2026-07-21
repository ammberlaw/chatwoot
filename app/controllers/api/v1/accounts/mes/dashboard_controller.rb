# 生产看板：聚合现有数据的只读总览。
class Api::V1::Accounts::Mes::DashboardController < Api::V1::Accounts::Mes::BaseController
  STALL_DAYS = 3
  DUE_SOON_DAYS = 3

  def show
    active = Current.account.mes_production_orders.where.not(status: 'CANCELLED')
    open_orders = active.where.not(stage: 'SHIPPED').includes(:stage_events)

    @in_production = open_orders.count
    @stage_distribution = active.group(:stage).count
    @overdue, @due_soon, @stalled = classify(open_orders)
    @shortages = shortages
    @month = month_output
    render 'api/v1/accounts/mes/dashboard/show'
  end

  private

  def classify(orders)
    now = Time.current
    overdue = []
    due_soon = []
    stalled = []
    orders.each do |po|
      row = order_row(po)
      if po.delivery_date.present? && po.delivery_date < now
        overdue << row.merge(days: ((now - po.delivery_date) / 1.day).ceil)
      elsif po.delivery_date.present? && po.delivery_date <= now + DUE_SOON_DAYS.days
        due_soon << row.merge(days: ((po.delivery_date - now) / 1.day).ceil)
      end
      ev = po.stage_events.find { |e| e.stage == po.stage }
      next unless ev

      days = ((now - ev.entered_at) / 1.day).floor
      stalled << row.merge(days: days) if days >= STALL_DAYS
    end
    [overdue.sort_by { |r| -r[:days] }, due_soon.sort_by { |r| r[:days] }, stalled.sort_by { |r| -r[:days] }]
  end

  def order_row(po)
    { id: po.id, order_no: po.order_no, product_name: po.product_name, stage: po.stage,
      delivery_date: po.delivery_date }
  end

  def shortages
    Current.account.mes_stock_balances.includes(:mes_material, :warehouse).where('qty <> 0')
           .select(&:short?)
           .map do |b|
      { material_name: b.mes_material&.name, warehouse_name: b.warehouse&.name,
        qty: b.qty, safety_stock: b.mes_material&.safety_stock }
    end
  end

  def month_output
    range = Time.current.beginning_of_month..Time.current.end_of_month
    recs = Current.account.mes_production_records.where(recorded_at: range)
    completed = recs.sum(:qty_completed)
    scrap = recs.sum(:qty_scrap)
    shipped = Current.account.mes_shipments.where(status: 'SHIPPED', shipped_at: range).count
    denom = completed + scrap
    qc = Current.account.mes_inspections.where(inspected_at: range)
    qc_total = qc.sum(:inspected_qty)
    qc_failed = qc.sum(:failed_qty)
    { completed: completed, scrap: scrap, shipped: shipped,
      yield_rate: denom.positive? ? (completed / denom.to_f).round(4) : nil,
      qc_inspected: qc_total, qc_failed: qc_failed,
      qc_pass_rate: qc_total.positive? ? ((qc_total - qc_failed) / qc_total.to_f).round(4) : nil }
  end
end
