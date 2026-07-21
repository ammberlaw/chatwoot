# 生产看板：聚合现有数据的只读总览。
class Api::V1::Accounts::Mes::DashboardController < Api::V1::Accounts::Mes::BaseController
  def show
    active = scoped_by_product_line(Current.account.mes_production_orders.where.not(status: 'CANCELLED'))
    @in_production = active.where.not(stage: 'SHIPPED').count
    @stage_distribution = active.group(:stage).count

    alerts = Mes::AlertScannerService.new(Current.account, product_line: current_product_line).call
    @overdue = alerts[:overdue]
    @due_soon = alerts[:due_soon]
    @stalled = alerts[:stalled]
    @unacked = alerts[:unacked]
    @month = period_output
    render 'api/v1/accounts/mes/dashboard/show'
  end

  private

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
