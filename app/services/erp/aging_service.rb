# 账龄分析：应收按客户、应付按供应商，把未结余额摊到各账龄段。
#
# 两种口径（金蝶同款，财务两种都要看）：
# - `due` **逾期账龄**：从到期日算，还没到期的单独一段。催款用这个。
# - `invoice` **账龄**：从建账日算，不看到期日。坏账计提用这个（账龄分析法）。
#
# 应收的未结金额要**摊到分期上**：收款是记在台账层的，按到期日先后 FIFO 冲抵分期，
# 剩下没冲掉的才是各期的未结额——否则一张有订金有尾款的单子，账龄只能算一个笼统的数。
# 金额一律折**本位币**（同一个客户可能既有美元单又有人民币单，不折没法加总）。
class Erp::AgingService
  DUE_BUCKETS = [
    { key: 'NOT_DUE', label: '未到期' },
    { key: 'D30', label: '逾期 1-30 天' },
    { key: 'D60', label: '31-60 天' },
    { key: 'D90', label: '61-90 天' },
    { key: 'D180', label: '91-180 天' },
    { key: 'D365', label: '181-365 天' },
    { key: 'OVER', label: '1 年以上' }
  ].freeze

  AGE_BUCKETS = [
    { key: 'D30', label: '30 天以内' },
    { key: 'D60', label: '31-60 天' },
    { key: 'D90', label: '61-90 天' },
    { key: 'D180', label: '91-180 天' },
    { key: 'D365', label: '181-365 天' },
    { key: 'OVER', label: '1 年以上' }
  ].freeze

  # 天数上界 → 段位，逐段比大小取第一个命中的。
  LADDER = [[30, 'D30'], [60, 'D60'], [90, 'D90'], [180, 'D180'], [365, 'D365']].freeze

  DUE = 'due'.freeze
  INVOICE = 'invoice'.freeze

  def initialize(account)
    @account = account
  end

  def receivables(as_of:, basis: DUE)
    with_context(as_of, basis) do
      docs = @account.erp_receivables.open.includes(:installments, :crm_customer)
                     .flat_map { |receivable| receivable_docs(receivable) }
      group(docs)
    end
  end

  def payables(as_of:, basis: DUE)
    with_context(as_of, basis) do
      group(@account.erp_payables.open.includes(:mes_supplier).map { |payable| payable_doc(payable) })
    end
  end

  private

  # 截至日与口径贯穿整趟计算，存成实例态，省得每个私有方法都拖着这两个参数走。
  def with_context(as_of, basis)
    @as_of = as_of
    @basis = basis
    yield
  end

  def invoice_basis?
    @basis == INVOICE
  end

  def buckets
    invoice_basis? ? AGE_BUCKETS : DUE_BUCKETS
  end

  # 应收：按到期日 FIFO 把已收款冲掉分期，剩余的才计入账龄。
  def receivable_docs(receivable)
    schedule(receivable).filter_map do |slot|
      next if slot[:open_micros] <= 0

      doc(receivable, party: receivable.crm_customer, doc_no: receivable.receivable_no,
                      slot: { date: slot[:due_date], open_micros: slot[:open_micros], note: slot[:note] })
    end
  end

  # 账龄口径只看建账日，整张台账算一段；逾期口径按分期铺开（FIFO 冲抵与催收预警、订单进度条同一套）。
  def schedule(receivable)
    return Erp::InstallmentFifo.settle(receivable) unless invoice_basis?

    [{ due_date: receivable.created_at.to_date, open_micros: receivable.outstanding_micros, note: nil }]
  end

  def payable_doc(payable)
    date = invoice_basis? ? payable.created_at.to_date : payable.due_date
    doc(payable, party: payable.mes_supplier, doc_no: payable.payable_no,
                 slot: { date: date, open_micros: payable.outstanding_micros, note: nil })
  end

  def doc(record, party:, doc_no:, slot:)
    date = slot[:date]
    {
      party_id: party&.id, party_name: party&.name,
      no: doc_no, date: date, note: slot[:note],
      currency: record.currency, open_micros: slot[:open_micros],
      base_micros: (slot[:open_micros] * record.exchange_rate).round,
      days: days_of(date), bucket: bucket_of(date)
    }
  end

  def not_due?(date)
    !invoice_basis? && (date.blank? || date >= @as_of)
  end

  def days_of(date)
    return nil if date.blank? || not_due?(date)

    (@as_of - date).to_i
  end

  def bucket_of(date)
    return 'NOT_DUE' if not_due?(date)
    return 'OVER' if date.blank?

    days = (@as_of - date).to_i
    LADDER.find { |limit, _| days <= limit }&.last || 'OVER'
  end

  def group(docs)
    keys = buckets.pluck(:key)
    rows = docs.group_by { |item| item[:party_id] }
               .map { |_, items| party_row(items, keys) }
               .sort_by { |row| -row[:total_micros] }

    { as_of: @as_of, basis: @basis, buckets: buckets, rows: rows, totals: totals_of(rows, keys) }
  end

  def party_row(items, keys)
    cells = keys.index_with { |key| items.select { |item| item[:bucket] == key }.sum { |item| item[:base_micros] } }
    {
      party_id: items.first[:party_id], party_name: items.first[:party_name],
      total_micros: items.sum { |item| item[:base_micros] }, cells: cells,
      documents: items.sort_by { |item| item[:date] || Date.new(9999) }
    }
  end

  def totals_of(rows, keys)
    {
      total_micros: rows.sum { |row| row[:total_micros] },
      cells: keys.index_with { |key| rows.sum { |row| row[:cells][key] } }
    }
  end
end
