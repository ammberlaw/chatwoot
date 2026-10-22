# 应付「待对账」：2026-10-21 财务定的流程——收了货先跟供应商核对，对好了才落应付台账。
# 过账时不再自动建账（见 Mes::StockEntry#post!），这里按**已过账收货**实时算该欠多少，
# 与台账已建的比，差额 ≠ 0 的才摆出来等人核。
#
# 建账动作本身仍走 LedgerBuilderService 的 upsert_payable，口径不分叉。
module Erp::PayableReconciliation
  # ── 应付「先对账再建账」 ──────────────────────────────────────────
  # 收了货不再直接起账（见 Mes::StockEntry#post!：自动建账那一步 2026-10-21 停掉了），
  # 先在这里按「采购单 × 供应商」把该欠多少列出来，财务跟供应商核对无误再确认建账。
  # 粒度与应付台账一行完全一致，确认走的就是原来那个 upsert——口径不会分叉。
  #
  # 只看**已过账**的原料入库：草稿单上的数字还会改，拿去跟供应商对账等于对了个寂寞。
  def pending_reconciliation
    order_ids = @account.mes_stock_entries
                        .where(purpose: 'MATERIAL_RECEIPT', status: 'POSTED')
                        .where.not(purchase_order_id: nil).distinct.pluck(:purchase_order_id)
    booked = booked_amounts(order_ids)
    dates = receipt_dates(order_ids)
    @account.mes_purchase_orders.where(id: order_ids)
            .includes(purchase_items: :mes_supplier)
            .flat_map { |order| reconciliation_rows(order, booked, dates) }
            .sort_by { |row| [row[:last_receipt_on].to_s, row[:po_no].to_s, row[:supplier_name].to_s] }
  end

  # 确认建账：按实收金额建/更新这一行（就是原来入库过账时自动做的那一步）。
  def confirm_reconciliation!(purchase_order:, supplier_id:)
    items = purchase_order.purchase_items.select { |item| item.mes_supplier_id == supplier_id }
    raise Error, "采购单 #{purchase_order.po_no} 上没有这家供应商的明细行" if items.empty?

    amount = received_amount(supplier_id, items)
    raise Error, '这家供应商在本单上还没有已过账的收货，没有可建账的金额' if amount <= 0

    upsert_payable(purchase_order, supplier_id, amount)
  end

  private

  # 实收金额：行上有金额的按「实收/订购」等比折算，没金额的按供应商报价 × 实收 × (1+税率)。
  # 差额 ≠ 0 才算待对账：一分不差就是已经对过账建过了，不该再占着清单。
  def reconciliation_rows(order, booked, dates)
    order.purchase_items.group_by(&:mes_supplier_id).filter_map do |supplier_id, items|
      next if supplier_id.blank?

      amount = received_amount(supplier_id, items)
      next if amount <= 0

      booked_micros = booked[[order.id, supplier_id]].to_i
      next if booked_micros == amount

      { mes_purchase_order_id: order.id, po_no: order.po_no, mes_supplier_id: supplier_id,
        supplier_name: items.first.mes_supplier&.name, received_micros: amount,
        booked_micros: booked_micros }.merge(dates.fetch([order.id, supplier_id], {}))
    end
  end

  # 这批采购单下每家供应商的收货日期（财务按月对账，表上没日期就无从下手）。
  # 入库单明细挂的是产品，要经采购行才知道这颗料是哪家的——同一张采购单上不同供应商
  # 的货未必同一天到。口径同 inbound_date_for：货到那天，没录到货日退回过账日。
  def receipt_dates(order_ids)
    return {} if order_ids.blank?

    @account.mes_stock_entries.posted
            .where(purpose: 'MATERIAL_RECEIPT', purchase_order_id: order_ids)
            .joins('JOIN mes_stock_entry_items sei ON sei.stock_entry_id = mes_stock_entries.id')
            .joins('JOIN mes_purchase_items pi ON pi.purchase_order_id = mes_stock_entries.purchase_order_id ' \
                   'AND pi.crm_product_id = sei.crm_product_id')
            .where.not(pi: { mes_supplier_id: nil })
            .group('mes_stock_entries.purchase_order_id', 'pi.mes_supplier_id')
            .pluck(Arel.sql(RECEIPT_DATE_SELECT))
            .to_h { |po_id, sup_id, first_on, last_on, count| [[po_id, sup_id], receipt_date_row(first_on, last_on, count)] }
  end

  RECEIPT_DATE_SELECT = 'mes_stock_entries.purchase_order_id, pi.mes_supplier_id, ' \
                        'MIN(COALESCE(actual_inbound_date, posted_at))::date, ' \
                        'MAX(COALESCE(actual_inbound_date, posted_at))::date, ' \
                        'COUNT(DISTINCT mes_stock_entries.id)'.freeze

  def receipt_date_row(first_on, last_on, count)
    { first_receipt_on: first_on, last_receipt_on: last_on, entry_count: count }
  end

  def booked_amounts(order_ids)
    @account.erp_payables.where(mes_purchase_order_id: order_ids)
            .pluck(:mes_purchase_order_id, :mes_supplier_id, :total_amount_micros)
            .to_h { |order_id, supplier_id, amount| [[order_id, supplier_id], amount] }
  end
end
