# 生产看板：聚合现有数据的只读总览。
class Api::V1::Accounts::Mes::DashboardController < Api::V1::Accounts::Mes::BaseController
  def show
    active = Current.account.mes_production_orders.where.not(status: 'CANCELLED')
    @in_production = active.where.not(stage: 'SHIPPED').count
    @stage_distribution = active.group(:stage).count

    alerts = Mes::AlertScannerService.new(Current.account).call
    @overdue = alerts[:overdue]
    @due_soon = alerts[:due_soon]
    @stalled = alerts[:stalled]
    @shortages = alerts[:shortages]
    @month = month_output
    render 'api/v1/accounts/mes/dashboard/show'
  end

  private

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
