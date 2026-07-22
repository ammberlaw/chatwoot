# 生产看板：聚合现有数据的只读总览。
class Api::V1::Accounts::Mes::DashboardController < Api::V1::Accounts::Mes::BaseController
  def show
    active = scoped_by_product_line(Current.account.mes_production_orders.published.where.not(status: 'CANCELLED'))
    @in_production = active.where.not(stage: 'SHIPPED').count
    @stage_distribution = active.group(:stage).count

    alerts = Mes::AlertScannerService.new(Current.account, product_line: current_product_line).call
    @overdue = alerts[:overdue]
    @due_soon = alerts[:due_soon]
    @stalled = alerts[:stalled]
    @unacked = alerts[:unacked]
    @month = period_output
    @on_time = on_time_by_line(period_range)
    render 'api/v1/accounts/mes/dashboard/show'
  end

  private

  # 按时交货率（按产品线）：SHIPPED 到达时间在区间内、有交期的订单，出货日 ≤ 交期日即按时。
  # 全产线一并算（不受切换器过滤），才能横向比较。
  def on_time_by_line(range)
    events = Current.account.mes_production_order_stage_events
                    .where(stage: 'SHIPPED', entered_at: range)
                    .includes(:production_order)
    by_line = Hash.new { |h, k| h[k] = { total: 0, on_time: 0 } }
    events.each do |ev|
      po = ev.production_order
      next if po.nil? || po.is_draft || po.delivery_date.nil?

      line = po.product_line.presence || 'UNKNOWN'
      by_line[line][:total] += 1
      by_line[line][:on_time] += 1 if ev.entered_at.to_date <= po.delivery_date.to_date
    end
    by_line.transform_values do |v|
      { total: v[:total], on_time: v[:on_time],
        rate: v[:total].positive? ? (v[:on_time].to_f / v[:total]).round(4) : nil }
    end
  end

  # 时间筛选：前端传 start_date/end_date（ISO 日期），缺省本月。
  def period_range
    start_at = params[:start_date].present? ? Time.zone.parse(params[:start_date]).beginning_of_day : Time.current.beginning_of_month
    end_at = params[:end_date].present? ? Time.zone.parse(params[:end_date]).end_of_day : Time.current.end_of_month
    start_at..end_at
  end

  def period_output
    range = period_range
    recs = scoped_by_product_line(Current.account.mes_production_records).where(recorded_at: range)
    completed = recs.sum(:qty_completed)
    scrap = recs.sum(:qty_scrap)
    shipped = scoped_by_product_line(Current.account.mes_shipments).where(status: 'SHIPPED', shipped_at: range).count
    denom = completed + scrap
    qc = scoped_by_product_line(Current.account.mes_inspections).where(inspected_at: range)
    qc_total = qc.sum(:inspected_qty)
    qc_failed = qc.sum(:failed_qty)
    { completed: completed, scrap: scrap, shipped: shipped,
      yield_rate: denom.positive? ? (completed / denom.to_f).round(4) : nil,
      qc_inspected: qc_total, qc_failed: qc_failed,
      qc_pass_rate: qc_total.positive? ? ((qc_total - qc_failed) / qc_total.to_f).round(4) : nil }
  end
end
