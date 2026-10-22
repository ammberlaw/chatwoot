# 台账建账：从业务单据一键生成应收/应付，金额带入后可改。
#
# 应收：一张销售订单一条账（重复建账直接拦），金额/币种/汇率/归属业务员都从订单带。
# 应付：按采购单**明细行的供应商分组**，每个供应商一条账——一张采购单向三家买料就是三条应付。
class Erp::LedgerBuilderService
  # 「待对账」是收货与建账之间独立的一段流程，方法成组地只服务那一件事——
  # 拆出去读起来更清楚，建账这边也回到它自己的职责上。
  include Erp::PayableReconciliation

  class Error < StandardError; end

  # 建账成功、但收入凭证没出来的原因（期间已结账、科目没配…）。
  # 凭证失败不回滚建账，但**必须让人看见**——静默失败就是「建完了却没凭证，没人知道为什么」。
  attr_reader :voucher_warning

  # 应付按实收重算时的异常（重算后低于已付等）。同样不能静默。
  attr_reader :payable_warning

  def initialize(account)
    @account = account
    @voucher_warning = nil
    @payable_warning = nil
  end

  def from_sales_order(order, installments: [])
    existing = @account.erp_receivables.find_by(crm_sales_order_id: order.id)
    raise Error, "订单 #{order.order_no} 已建过应收账（#{existing.receivable_no}），请直接在台账里改" if existing

    receivable = @account.erp_receivables.create!(
      crm_sales_order_id: order.id,
      crm_customer_id: order.crm_customer_id,
      currency: order.order_currency.presence || 'CNY',
      exchange_rate: order.exchange_rate.presence || 1,
      # 建账金额＝收入+销项税（客户实付），不是订单金额原值：不含税单的订单金额
      # 只是收入，税要另加。出库收入凭证的应收借方取的也是这个数，两边才对得上。
      total_amount_micros: order.receivable_amount_micros,
      owner_id: order.owner_id,
      remark: "由销售订单 #{order.order_no} 建账"
    )
    build_installments(receivable, installments, order)
    # 已出货/已完结的订单建账即出收入凭证。没走 MES 出库的历史订单（小满迁入的、
    # 系统外发货的）等不到出库那个触发点，不在这里补就只有台账没有总账，两账对不平。
    # 待出货的订单不出（见 AutoVoucherService#receivable_revenue_bookable?）。
    generate_revenue_voucher(receivable)
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
        settle_type: settle_type_for(purchase_order, supplier_id),
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
    (net * (1 + (supplier.tax_rate.to_d / 100)) * 1_000_000).round
  end

  def unit_price_for(supplier, item)
    return item.rate_micros.to_d / 1_000_000 if item.rate_micros.to_i.positive?

    supplier.supplier_items.find_by(mes_material_id: item.mes_material_id)&.unit_price.to_d
  end

  private

  def received_amount(supplier_id, items)
    supplier = @account.mes_suppliers.find_by(id: supplier_id)
    items.sum { |item| received_line_amount(supplier, item) }
  end

  def received_line_amount(supplier, item)
    received = item.received_qty.to_d
    return 0 if received <= 0

    priced = item.amount_micros.to_i.positive? && item.qty.to_d.positive?
    return (item.amount_micros.to_d * received / item.qty.to_d).round if priced
    return 0 if supplier.blank?

    (received * unit_price_for(supplier, item) * (1 + (supplier.tax_rate.to_d / 100)) * 1_000_000).round
  end

  def upsert_payable(purchase_order, supplier_id, amount)
    payable = @account.erp_payables.find_by(mes_purchase_order_id: purchase_order.id, mes_supplier_id: supplier_id)
    return create_receipt_payable(purchase_order, supplier_id, amount) if payable.nil?

    if amount < payable.paid_amount_micros.to_i
      @payable_warning = "应付 #{payable.payable_no} 按实收重算为 #{fmt(amount)}，低于已付 #{fmt(payable.paid_amount_micros)}，" \
                         '未改动——请先核对收货数量或撤销相关付款核销'
      return payable
    end

    payable.update!(total_amount_micros: amount)
    # 先建账后入库的单，建账那会儿还没有货到日，这里补上。已经有值的不动。
    payable.update!(incurred_on: inbound_date_for(purchase_order)) if payable.incurred_on.blank?
    payable.update!(status: payable.derived_status)
    payable
  end

  def create_receipt_payable(purchase_order, supplier_id, amount)
    @account.erp_payables.create!(
      mes_purchase_order_id: purchase_order.id,
      mes_supplier_id: supplier_id,
      total_amount_micros: amount,
      settle_type: settle_type_for(purchase_order, supplier_id),
      incurred_on: inbound_date_for(purchase_order),
      remark: "由采购单 #{purchase_order.po_no} 入库建账"
    )
  end

  # 发生日期＝货到那天，取这张采购单最后一次入库。分批到货就跟着往后走，财务按它分月。
  # 原料采购入库单上没有「实际入库日」这一栏（只有成品入库才录），所以回落到过账时间——
  # 仓管点过账就是确认货到那一刻，不用谁多录一个日期。单据还没过账过就留空。
  def inbound_date_for(purchase_order)
    @account.mes_stock_entries.posted
            .where(purchase_order_id: purchase_order.id)
            .maximum(Arel.sql('COALESCE(actual_inbound_date, posted_at)'))&.to_date
  end

  # 含税 / 未税：这一单指定了就按单走，没指定就取该供应商档案上的默认值。
  def settle_type_for(purchase_order, supplier_id)
    purchase_order.settle_type.presence ||
      @account.mes_suppliers.find_by(id: supplier_id)&.default_settle_type ||
      Erp::Payable::PUBLIC
  end

  def fmt(micros) = format('%.2f', micros.to_i / 1_000_000.0)

  # 凭证失败不该让建账整个回滚——台账是业务账、先落住。但原因要带回给调用方显示，
  # 只写日志等于让财务对着一条没凭证的台账猜。
  def generate_revenue_voucher(receivable)
    Erp::AutoVoucherService.new(@account).for_receivable_revenue(receivable)
  rescue StandardError => e
    Rails.logger.error("[Erp::AutoVoucher] 应收 #{receivable.receivable_no} 生成收入凭证失败: #{e.message}")
    @voucher_warning = "台账 #{receivable.receivable_no} 已建，但收入凭证没生成：#{e.message.delete_prefix('Validation failed: ')}"
  end

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
