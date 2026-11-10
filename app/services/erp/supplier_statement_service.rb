# 供应商月度对账单：一家供应商、一个月，这个月进了多少货、退了多少、该付多少，
# 列到物料级，导出给供应商签字确认（Amber 2026-11-09：「财务需要根据采购入库单和
# 退货单对供应商单月的账做凭证」）。
#
# ⚠️ 主体按**单据**算，不按应付台账。
# 「先对账再建账」2026-10-21 上线之后财务一笔都没确认过：台账停在 59 行（全是 10-19
# 之前自动建的），11 月 56 张入库单对应 0 行台账，付款记录 0 条。按台账算的话对账单
# 整月是一片 0，而货实实在在收了。台账与付款只摆在旁边当参考，并把「这个月还有多少
# 没建台账」明着标出来——那个差额就是财务对完账要补的动作。
#
# 金额口径与应付凭证同源（Erp::AutoVoucherService#receipt_rows：本次入库数量 × 采购单价），
# 供应商也和凭证一样取自采购单行——入库单明细挂的是产品，同一张采购单上不同物料
# 可能来自不同供应商。
class Erp::SupplierStatementService
  PURPOSES = %w[MATERIAL_RECEIPT PURCHASE_RETURN].freeze

  def initialize(account:, month: nil)
    @account = account
    @month = (month.presence ? Date.parse("#{month}-01") : Date.current).beginning_of_month
  end

  # 本月一览：每家供应商进了多少、退了多少、净额多少、建了多少台账、出了几张凭证。
  # 财务一屏看全貌，再决定先跟哪家对。
  def summary
    by_supplier = Hash.new { |h, k| h[k] = { receipt_micros: 0, return_micros: 0, entry_count: 0 } }
    # 一张单里同一家供应商可能拆成几行存货科目（料的类别不同），单数要按单去重，
    # 不然 3 张单会报成 17 单，财务拿去跟供应商核「你这个月送了几次货」直接对不上。
    counted = Set.new
    each_entry_row do |entry, supplier_id, amount|
      bucket = by_supplier[supplier_id]
      bucket[return_entry?(entry) ? :return_micros : :receipt_micros] += amount
      bucket[:entry_count] += 1 if counted.add?([entry.id, supplier_id])
    end
    { month: month_key, from: @month, to: period_end, rows: summary_rows(by_supplier) }
  end

  # 单家明细：按单据列，每单带物料行。
  def detail(supplier_id)
    supplier = @account.mes_suppliers.find(supplier_id)
    docs = detail_docs(supplier_id)
    receipt = docs.reject { |d| d[:kind] == 'RETURN' }.sum { |d| d[:amount_micros] }
    ret = docs.select { |d| d[:kind] == 'RETURN' }.sum { |d| d[:amount_micros] }
    { month: month_key, from: @month, to: period_end,
      supplier: { id: supplier.id, name: supplier.name },
      docs: docs, receipt_micros: receipt, return_micros: ret, net_micros: receipt - ret }
      .merge(ledger_side(supplier_id)).merge(voucher_stats(docs))
  end

  # 对完账那一下要过的就是 draft_voucher_ids（前端直接喂凭证的 bulk_post，不另造接口）。
  def voucher_stats(docs)
    by_status = docs.group_by { |d| d[:voucher]&.dig(:status) }
    { posted_count: by_status[Erp::Voucher::POSTED].to_a.size,
      draft_count: by_status[Erp::Voucher::DRAFT].to_a.size,
      no_voucher_count: by_status[nil].to_a.size,
      draft_voucher_ids: by_status[Erp::Voucher::DRAFT].to_a.map { |d| d[:voucher][:id] } }
  end

  private

  def month_key = @month.strftime('%Y-%m')
  def period_end = @month.end_of_month
  def return_entry?(entry) = entry.purpose == 'PURCHASE_RETURN'

  # 对账按「货到那天」排期，不是财务录单那天——口径同 Erp::PayableReconciliation。
  # 原料采购入库页没有「实际到货日」这一栏，取不到就退回过账日。
  def doc_date(entry) = entry.actual_inbound_date || entry.posted_at&.to_date

  def entries
    @entries ||= @account.mes_stock_entries.posted
                         .where(purpose: PURPOSES)
                         .where('COALESCE(actual_inbound_date, posted_at::date) BETWEEN ? AND ?',
                                @month, period_end)
                         .includes(:purchase_order, { stock_entry_items: :crm_product })
                         .order(:posted_at, :id).to_a
  end

  def voucher_service = @voucher_service ||= Erp::AutoVoucherService.new(@account)

  def each_entry_row
    entries.each do |entry|
      voucher_service.receipt_rows(entry).each do |row|
        next if row[:supplier_id].blank? || row[:amount].to_i <= 0

        yield entry, row[:supplier_id], row[:amount].to_i
      end
    end
  end

  def summary_rows(by_supplier)
    names = @account.mes_suppliers.where(id: by_supplier.keys).pluck(:id, :name).to_h
    rows = by_supplier.map { |supplier_id, bucket| summary_row(supplier_id, bucket, names) }
    rows.sort_by { |row| [-row[:net_micros], row[:supplier_name].to_s] }
  end

  def summary_row(supplier_id, bucket, names)
    net = bucket[:receipt_micros] - bucket[:return_micros]
    booked = booked_by_supplier[supplier_id].to_i
    bucket.merge(mes_supplier_id: supplier_id, supplier_name: names[supplier_id],
                 net_micros: net, booked_micros: booked, unbooked_micros: net - booked)
          .merge(voucher_stats_by_supplier[supplier_id])
  end

  # 本月建了多少应付台账（按发生日期落月，口径同 Erp::PayableMonthlyService）。
  def booked_by_supplier
    @booked_by_supplier ||= @account.erp_payables
                                    .where('COALESCE(incurred_on, created_at::date) BETWEEN ? AND ?',
                                           @month, period_end)
                                    .group(:mes_supplier_id).sum(:total_amount_micros)
  end

  # 本月这家供应商的单，凭证各是什么状态。
  # 只报一个「出了几张」没用——财务要分清「还没出」「出了待过账」「已记账」三种，
  # 待过账的那一堆才是对完账要按下去的那一下。
  def voucher_stats_by_supplier
    @voucher_stats_by_supplier ||= begin
      stats = Hash.new { |h, k| h[k] = { posted_count: 0, draft_count: 0, no_voucher_count: 0 } }
      seen = Set.new
      each_entry_row do |entry, supplier_id, _amount|
        next unless seen.add?([entry.id, supplier_id])

        stats[supplier_id][voucher_stat_key(entry)] += 1
      end
      stats
    end
  end

  def voucher_stat_key(entry)
    case voucher_for(entry)&.dig(:status)
    when Erp::Voucher::POSTED then :posted_count
    when Erp::Voucher::DRAFT then :draft_count
    else :no_voucher_count
    end
  end

  def detail_docs(supplier_id)
    entries.filter_map { |entry| detail_doc(entry, supplier_id) }
  end

  def detail_doc(entry, supplier_id)
    amount = voucher_service.receipt_rows(entry)
                            .select { |r| r[:supplier_id] == supplier_id }
                            .sum { |r| r[:amount].to_i }
    return if amount <= 0

    { kind: return_entry?(entry) ? 'RETURN' : 'RECEIPT', date: doc_date(entry),
      entry_no: entry.entry_no, po_no: entry.purchase_order&.po_no,
      amount_micros: amount, items: detail_items(entry, supplier_id),
      voucher: voucher_for(entry) }
  end

  # 物料行：对账单要给供应商看「哪颗料、几个、什么价」，只给总额对方没法核。
  def detail_items(entry, supplier_id)
    po_lines = entry.purchase_order&.purchase_items || []
    entry.stock_entry_items.filter_map do |item|
      line = purchase_line_for(po_lines, item, supplier_id)
      line && detail_item(item, line)
    end
  end

  # 这颗料在采购单上对应哪一行——供应商和单价都只有那里有。
  # 没有金额或数量为 0 的行算不出单价，摆进对账单只会是一行 0（同凭证口径：跳过）。
  def purchase_line_for(po_lines, item, supplier_id)
    po_lines.find do |line|
      line.crm_product_id.present? && line.crm_product_id == item.crm_product_id &&
        line.mes_supplier_id == supplier_id && line.qty.to_d.positive?
    end
  end

  # 料号/名称/规格在产品档案上，入库明细行本身只有数量和单位（料号＝产品 SKU）。
  def detail_item(item, line)
    qty = (item.received_qty.presence || item.qty).to_d
    rate = line.amount_micros.to_d / line.qty.to_d
    product = item.crm_product
    { material_no: product&.sku, material_name: product&.name,
      specification: product&.specification, qty: qty.to_f, unit: item.unit,
      rate_micros: rate.round, amount_micros: Erp::VoucherLine.round_to_cent(qty * rate) }
  end

  # 凭证的 id 和状态都要给出去：财务对完账要一键过账这个月这家的凭证，
  # 得先看清哪几张已过账、哪几张还是草稿、哪几张压根没出。
  # 作废的不算——它在账上等于不存在，摆出来只会被当成「已经有凭证了」。
  def voucher_for(entry)
    @vouchers ||= @account.erp_vouchers
                          .where(source_type: 'Mes::StockEntry', source_id: entries.map(&:id))
                          .where.not(status: Erp::Voucher::VOID)
                          .pluck(:source_id, :id, :voucher_no, :status)
                          .to_h { |src, id, no, st| [src, { id: id, voucher_no: no, status: st }] }
    @vouchers[entry.id]
  end

  # 台账侧：本月建了多少、还差多少、付了多少。期初/期末未付交给应付台账那套算，
  # 这里不另起炉灶（Erp::PayableMonthlyService 已经处理了外币折本位币和跨月核销）。
  def ledger_side(supplier_id)
    booked = booked_by_supplier[supplier_id].to_i
    { booked_micros: booked, paid_micros: paid_in_month(supplier_id) }
  end

  def paid_in_month(supplier_id)
    Erp::PaymentAllocation.joins(:payment_record, :payable)
                          .where(account_id: @account.id)
                          .where(erp_payment_records: { status: Erp::PaymentRecord::NORMAL })
                          .where(erp_payables: { mes_supplier_id: supplier_id })
                          .where('erp_payment_records.paid_at BETWEEN ? AND ?', @month, period_end)
                          .sum(:amount_micros)
  end
end
