# 销售订单的生产追溯：这张单在 MES 里走过的全程——生产订单是什么产品、各阶段什么时候进的、
# 领料/入库/出库单各是哪几张、出货单走到哪一步。
#
# 业务问的是「这单完结的到底是什么、什么时候领的料、有没有入库、什么时候出的货」，
# 这些分散在生产订单/阶段事件/出入库单/出货单四张表里，这里一次拼齐。
class Crm::SalesOrderTraceService
  # 出入库单一表多用，用途决定它是"领料"还是"入库"还是"出库"。
  PURPOSE_LABELS = {
    'MATERIAL_RECEIPT' => '原料入库', 'MATERIAL_ISSUE' => '生产领料',
    'MATERIAL_RETURN' => '退料', 'MANUFACTURE' => '成品入库',
    'SCRAP' => '清尾报废', 'SHIPMENT' => '成品出库'
  }.freeze
  ENTRY_STATUS_LABELS = { 'DRAFT' => '草稿', 'POSTED' => '已过账', 'CANCELLED' => '已取消' }.freeze
  SHIPMENT_STATUS_LABELS = {
    'DRAFT' => '草稿', 'PENDING_APPROVAL' => '待审核', 'APPROVED' => '待出库',
    'REJECTED' => '已驳回', 'SHIPPED' => '已出库', 'CANCELLED' => '已取消'
  }.freeze

  def initialize(account:, sales_order:)
    @account = account
    @sales_order = sales_order
  end

  def call
    orders = production_orders
    ids = orders.map(&:id)
    entries = stock_entries_by_order(ids)
    @records = records_by_order(ids)
    @inspections = inspections_by_order(ids)
    { production_orders: orders.map { |po| order_json(po, entries[po.id] || []) },
      shipments: shipments(ids).map { |s| shipment_json(s) } }
  end

  private

  def production_orders
    @account.mes_production_orders
            .where(crm_sales_order_id: @sales_order.id)
            .includes(:stage_events, bom: :bom_items).order(:created_at)
  end

  # 报工 / 质检整批查一次，逐单查就是一页几十条 SQL。
  def records_by_order(order_ids)
    @account.mes_production_records.where(production_order_id: order_ids)
            .includes(:operator).order(:recorded_at, :id).group_by(&:production_order_id)
  end

  def inspections_by_order(order_ids)
    @account.mes_inspections.where(production_order_id: order_ids)
            .order(:inspected_at, :id).group_by(&:production_order_id)
  end

  def stock_entries_by_order(order_ids)
    @account.mes_stock_entries
            .where(production_order_id: order_ids)
            .order(:created_at).group_by(&:production_order_id)
  end

  # Mes::StockEntry 上没有 from/to_warehouse 关联，只有裸 id 列（别处也是前端自己拿 id 换名）。
  # 这里一次把仓库表读成 id→名字，服务端换好再回给前端，避免逐条查库。
  def warehouse_names
    @warehouse_names ||= @account.mes_warehouses.pluck(:id, :name).to_h
  end

  # 出货单按「销售订单」挂——现货出库(STOCK)没有生产订单也能挂上，
  # 只顺着生产订单找会把这类单整个漏掉（已完结的单里就有这种）。
  def shipments(order_ids)
    scope = @account.mes_shipments.includes(:warehouse, :production_order, shipment_items: :crm_product)
    scope.where(crm_sales_order_id: @sales_order.id)
         .or(scope.where(production_order_id: order_ids))
         .order(:created_at)
  end

  def order_json(order, entries)
    { id: order.id, order_no: order.order_no, product_name: order.product_name, product_code: order.product_code,
      qty: order.qty.to_f, unit: order.unit, stage: order.stage,
      stage_label: Mes::ProductionOrder::STAGE_LABELS[order.stage] || order.stage,
      status: order.status, is_outsourced: order.is_outsourced,
      stages: stage_events_json(order), stock_entries: entries.map { |e| entry_json(e) },
      bom: bom_json(order), records: (@records[order.id] || []).map { |r| record_json(r) },
      inspections: (@inspections[order.id] || []).map { |i| inspection_json(i) } }
  end

  # BOM 用量：财务/业务在订单上核「这单要用哪些料、各多少」，不必再去 MES 翻生产任务单。
  # ⚠️ 只给料号/品名/用量——单价、供应商不进这里（销售端不可见，生态硬约束）。
  def bom_json(order)
    bom = order.bom
    return nil if bom.blank?

    { bom_no: bom.bom_no, base_qty: bom.base_qty.to_f,
      items: bom.bom_items.map do |item|
        # ⚠️ 只给料号/品名/规格/用量。BomItem 上还有 rate_micros / amount_micros
        # （采购单价与金额），一个都不能下发——这个接口是销售和财务在看，
        # 销售端不可见成本是硬规定。
        { material_no: item.material_no, name: item.material_name, spec: item.specification,
          qty: item.qty.to_f, unit: item.unit, category: item.category }
      end }
  end

  def record_json(record)
    { operation_name: record.operation_name, qty_completed: record.qty_completed.to_f,
      qty_scrap: record.qty_scrap.to_f, qty_returned: record.qty_returned.to_f,
      recorded_at: record.recorded_at, operator_name: record.operator&.name, remark: record.remark }
  end

  def inspection_json(inspection)
    { kind: inspection.kind, result: inspection.result,
      inspected_qty: inspection.inspected_qty.to_f, passed_qty: inspection.passed_qty.to_f,
      failed_qty: inspection.failed_qty.to_f, need_rework: inspection.need_rework,
      defect_reason: inspection.defect_reason, inspected_at: inspection.inspected_at }
  end

  # 按「进入时间」排，不按 id——补录/回退会让 id 序和真实时间序对不上。
  def stage_events_json(order)
    order.stage_events.sort_by { |e| e.entered_at || e.created_at }.map do |event|
      { stage: event.stage, label: Mes::ProductionOrder::STAGE_LABELS[event.stage] || event.stage,
        entered_at: event.entered_at, acked_at: event.acked_at }
    end
  end

  def entry_json(entry)
    { entry_no: entry.entry_no, purpose: entry.purpose,
      purpose_label: PURPOSE_LABELS[entry.purpose] || entry.purpose,
      status: entry.status, status_label: ENTRY_STATUS_LABELS[entry.status] || entry.status,
      created_at: entry.created_at, posted_at: entry.posted_at,
      actual_inbound_date: entry.actual_inbound_date,
      from_warehouse: warehouse_names[entry.from_warehouse_id],
      to_warehouse: warehouse_names[entry.to_warehouse_id] }
  end

  def shipment_json(shipment)
    { id: shipment.id, shipment_no: shipment.shipment_no, kind: shipment.kind,
      kind_label: shipment.kind == 'STOCK' ? '现货出库' : '生产出库',
      status: shipment.status,
      status_label: SHIPMENT_STATUS_LABELS[shipment.status] || shipment.status,
      submitted_at: shipment.submitted_at, approved_at: shipment.approved_at,
      shipped_at: shipment.shipped_at, warehouse: shipment.warehouse&.name,
      production_order_no: shipment.production_order&.order_no,
      items: shipment.shipment_items.map { |i| shipment_item_json(i) } }
  end

  # 「这张单到底出了什么货、各多少」——不带价（出库单本来就没有价，价也不该漏给销售端）。
  # 规格与颜色跟 MES 出库单查看弹窗同一套列：同一张出货单，财务在 ERP 看到的
  # 不该比仓管在 MES 看到的少（2026-11-03 用户核对两边明细时发现差三列）。
  def shipment_item_json(item)
    { product_name: item.crm_product&.name, product_sku: item.crm_product&.sku,
      specification: item.crm_product&.specification, color: item.color,
      qty: item.qty.to_f, unit: item.unit, remark: item.remark }
  end
end
