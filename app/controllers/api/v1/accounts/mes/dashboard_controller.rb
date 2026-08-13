# 生产看板：聚合现有数据的只读总览。
class Api::V1::Accounts::Mes::DashboardController < Api::V1::Accounts::Mes::BaseController
  def show
    # 业务员只统计/预警自己的订单（管理员/主管按范围，操作岗看全部）。
    owner_ids = mes_visible_owner_ids
    active = scoped_by_owner(scoped_by_product_line(Current.account.mes_production_orders.published.where.not(status: 'CANCELLED')))
    @in_production = active.where.not(stage: 'SHIPPED').count
    @stage_distribution = active.group(:stage).count

    assign_alerts(
      Mes::AlertScannerService.new(Current.account, product_line: current_product_line, owner_ids: owner_ids).call
    )
    @month = period_output
    @on_time = on_time_by_line(period_range)
    @ack_response = ack_response_by_stage(period_range)
    render 'api/v1/accounts/mes/dashboard/show'
  end

  private

  # 各环节接单响应时长：接单时刻 − 进入本环节时刻，按本期内发生的接单聚合。
  # 顶层按 6 个接单环节，每环节下钻到接单人（stage_events.acked_by）。未接单不计入。
  def ack_response_by_stage(range)
    grouped = ack_events_in(range).group_by(&:stage)
    names = ack_actor_names(grouped.values.flatten)
    Mes::ProductionOrder::STAGE_BOARD_KEYS.keys.filter_map do |stage|
      ack_stage_summary(stage, grouped[stage], names) if grouped[stage].present?
    end
  end

  def ack_stage_summary(stage, evs, names)
    durations = evs.map { |e| ack_seconds(e) }
    { stage: stage, label: Mes::ProductionOrder::STAGE_LABELS[stage],
      count: durations.size, avg_seconds: durations.sum / durations.size,
      people: ack_people(evs, names) }
  end

  # 环节内按接单人拆分，接单单数多者在前。
  def ack_people(evs, names)
    people = evs.group_by(&:acked_by_id).map do |uid, group|
      secs = group.map { |e| ack_seconds(e) }
      { name: names[uid] || '未知', count: secs.size, avg_seconds: secs.sum / secs.size }
    end
    people.sort_by { |p| -p[:count] }
  end

  def ack_actor_names(events)
    Current.account.users.where(id: events.filter_map(&:acked_by_id).uniq).pluck(:id, :name).to_h
  end

  # 响应时长按工作时间累计：工作日 08:00–17:30、跳周末（见 working_hours 初始化）。
  def ack_seconds(event)
    WorkingHours.working_time_between(event.entered_at, event.acked_at).to_i
  end

  # 本期内已接单的阶段事件（限 6 个接单环节），按可见范围 + 产品线收敛。
  def ack_events_in(range)
    orders = scoped_by_owner(scoped_by_product_line(Current.account.mes_production_orders))
    Current.account.mes_production_order_stage_events
           .where(stage: Mes::ProductionOrder::STAGE_BOARD_KEYS.keys)
           .where.not(acked_at: nil).where(acked_at: range)
           .where(production_order_id: orders.select(:id))
           .to_a
  end

  def assign_alerts(alerts)
    @overdue = alerts[:overdue]
    @due_soon = alerts[:due_soon]
    @stalled = alerts[:stalled]
    @unacked = alerts[:unacked]
  end

  # 按时交货率（按产品线）：口径为「成品入库」。出不出库由业务决定、非生产可控，
  # 故绩效算到成品入库为止——FG_INBOUND 到达时间在区间内、有客户交期的订单，
  # 成品入库日 ≤ 交期日即按时。备货订单无客户交期，自动不计入（下方 nil 跳过）。
  # 全产线一并算（不受切换器过滤），才能横向比较。
  def on_time_by_line(range)
    events = Current.account.mes_production_order_stage_events
                    .where(stage: 'FG_INBOUND', entered_at: range)
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
