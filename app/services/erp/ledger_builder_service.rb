# 台账建账：从业务单据一键生成应收/应付，金额带入后可改。
#
# 应收：一张销售订单一条账（重复建账直接拦），金额/币种/汇率/归属业务员都从订单带。
# 应付：按采购单**明细行的供应商分组**，每个供应商一条账——一张采购单向三家买料就是三条应付。
class Erp::LedgerBuilderService
  class Error < StandardError; end

  def initialize(account)
    @account = account
  end

  def from_sales_order(order, installments: [])
    existing = @account.erp_receivables.find_by(crm_sales_order_id: order.id)
    raise Error, "订单 #{order.order_no} 已建过应收账（#{existing.receivable_no}），请直接在台账里改" if existing

    receivable = @account.erp_receivables.create!(
      crm_sales_order_id: order.id,
      crm_customer_id: order.crm_customer_id,
      currency: order.order_currency.presence || 'CNY',
      exchange_rate: order.exchange_rate.presence || 1,
      total_amount_micros: order.order_amount_micros.to_i,
      owner_id: order.owner_id,
      remark: "由销售订单 #{order.order_no} 建账"
    )
    build_installments(receivable, installments, order)
    receivable
  end

  # 返回生成的应付数组；已建过账的供应商跳过（不重复建）。
  def from_purchase_order(purchase_order)
    grouped = purchase_order.purchase_items.group_by(&:mes_supplier_id).reject { |supplier_id, _| supplier_id.blank? }
    raise Error, "采购单 #{purchase_order.po_no} 的明细行没有指定供应商，无法建应付" if grouped.empty?

    existing_suppliers = @account.erp_payables.where(mes_purchase_order_id: purchase_order.id).pluck(:mes_supplier_id)
    grouped.filter_map do |supplier_id, items|
      next if existing_suppliers.include?(supplier_id)

      amount = supplier_amount(supplier_id, items)
      next if amount <= 0

      @account.erp_payables.create!(
        mes_purchase_order_id: purchase_order.id,
        mes_supplier_id: supplier_id,
        total_amount_micros: amount,
        remark: "由采购单 #{purchase_order.po_no} 建账"
      )
    end
  end

  # 金额优先取采购明细上的行金额；行上没有金额（MES 侧未填价）就按供应商报价单算：
  # Σ(数量 × SupplierItem 未税单价) × (1 + 供应商税率)，与 ERP_SPEC §3.1 口径一致。
  def supplier_amount(supplier_id, items)
    from_lines = items.sum { |item| item.amount_micros.to_i }
    return from_lines if from_lines.positive?

    supplier = @account.mes_suppliers.find_by(id: supplier_id)
    return 0 if supplier.blank?

    net = items.sum { |item| item.qty.to_d * unit_price_for(supplier, item) }
    (net * (1 + supplier.tax_rate.to_d / 100) * 1_000_000).round
  end

  def unit_price_for(supplier, item)
    return item.rate_micros.to_d / 1_000_000 if item.rate_micros.to_i.positive?

    supplier.supplier_items.find_by(mes_material_id: item.mes_material_id)&.unit_price.to_d
  end

  private

  # 没给分期就整单一期尾款；给了就按 [{kind:, amount_micros:, due_basis:, due_days:, due_date:}] 建。
  def build_installments(receivable, specs, order)
    rows = specs.presence || [{ kind: 'BALANCE', amount_micros: receivable.total_amount_micros, due_basis: 'FIXED' }]
    rows.each_with_index do |spec, index|
      receivable.installments.create!(
        account_id: @account.id,
        seq: index + 1,
        kind: spec[:kind].presence || 'BALANCE',
        amount_micros: spec[:amount_micros].to_i,
        due_basis: spec[:due_basis].presence || 'FIXED',
        due_days: spec[:due_days],
        due_date: resolve_due_date(spec, order),
        remark: spec[:remark]
      )
    end
  end

  # 按约定条件推到期日：能算的算出来（下单后N天/出货后N天/出货前），
  # 算不出的（见提单副本）留空，等业务侧拿到单据再回填。
  DUE_ANCHORS = {
    'ORDER_DATE' => ->(order) { order.order_date },
    'AFTER_SHIPMENT' => ->(order) { order.delivery_date },
    'BEFORE_SHIPMENT' => ->(order) { order.delivery_date }
  }.freeze
  OFFSET_BASES = %w[ORDER_DATE AFTER_SHIPMENT].freeze

  def resolve_due_date(spec, order)
    return spec[:due_date] if spec[:due_date].present?

    anchor = order.present? ? DUE_ANCHORS[spec[:due_basis]]&.call(order)&.to_date : nil
    return nil if anchor.blank?

    OFFSET_BASES.include?(spec[:due_basis]) ? anchor + spec[:due_days].to_i : anchor
  end
end
