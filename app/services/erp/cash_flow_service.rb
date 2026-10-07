# 现金流量表（准则第31号，直接法）。基于已记账凭证实时算，不落中间表。
#
# 取数口径：本期所有**货币资金科目**（account_type CASH/BANK）的分录行，
# 借方＝流入、贷方＝流出，按现金流量项目归集（分录行手工指定优先，没指定按对方科目推断）。
#
# 三条会计口径（都容易做错）：
# 1. **内部划转不是现金流量**：银行→现金、人民币户→美元户，整张凭证两边都是货币资金，
#    直接整张跳过。不跳的话流入流出各虚增一笔，三大活动金额全是错的。
# 2. **汇兑损益不进三大活动**：对方科目是「汇兑损益」的现金变动属于「汇率变动对现金的影响」，
#    单列一行，否则会被当成经营活动其他流出。
# 3. **勾稽**：经营+投资+筹资净额 + 汇率变动影响 应当 = 期末现金 − 期初现金。
#    对不上就是账有问题（或有现金科目被漏配 account_type），报表直接把差额摆出来。
class Erp::CashFlowService
  CASH_TYPES = %w[CASH BANK].freeze
  EXCHANGE_DIFF = 'EXCHANGE_DIFF'.freeze
  OPENING_SOURCE = 'Erp::OpeningBalance'.freeze

  def initialize(account)
    @account = account
  end

  def statement(from:, to:)
    cash_ids = cash_account_ids
    buckets = Hash.new(0)
    fx_effect = 0

    vouchers_touching_cash(cash_ids, from, to).each do |voucher|
      cash_lines, other_lines = voucher.lines.partition { |line| cash_ids.include?(line.ledger_account_id) }
      next if other_lines.empty? # 内部划转

      cash_lines.each do |line|
        item, signed = classify(line, other_lines)
        if item.nil?
          fx_effect += signed
        else
          buckets[item] += natural_amount(item, line)
        end
      end
    end

    build_report(from: from, to: to, buckets: buckets, fx_effect: fx_effect, cash_ids: cash_ids)
  end

  private

  def cash_account_ids
    @account.erp_ledger_accounts.leaves.where(account_type: CASH_TYPES).pluck(:id)
  end

  def posted_cash_lines(cash_ids)
    @account.erp_voucher_lines
            .joins(:voucher)
            .where(erp_vouchers: { status: Erp::Voucher::POSTED })
            .where(ledger_account_id: cash_ids)
  end

  # 期初建账凭证排除在流量之外：它记的是**期初余额**，不是本期收支。
  # （不排的话账套启用当期会凭空多出一笔「吸收投资收到的现金」。IS DISTINCT FROM 才能连 NULL 一起留下。）
  def vouchers_touching_cash(cash_ids, from, to)
    ids = posted_cash_lines(cash_ids).where(erp_vouchers: { voucher_date: from..to }).distinct.pluck(:voucher_id)
    @account.erp_vouchers.where(id: ids)
            .where('source_type IS DISTINCT FROM ?', OPENING_SOURCE)
            .includes(lines: :ledger_account)
  end

  # 返回 [项目编码, 带符号金额]；项目编码为 nil 表示这笔算「汇率变动影响」。
  def classify(line, other_lines)
    inflow = line.direction == Erp::VoucherLine::DEBIT
    signed = inflow ? line.base_amount_micros : -line.base_amount_micros
    counterpart = counterpart_of(line, other_lines)
    return [nil, signed] if counterpart&.ledger_account&.account_type == EXCHANGE_DIFF

    [line.cash_flow_item.presence || Erp::CashFlowItem.infer(counterpart&.ledger_account&.code, inflow: inflow), signed]
  end

  # 落到项目里的金额要**带符号**，按「该项目的天然方向」算：
  #   流入项目 + 现金增加 → 正；流入项目 + 现金减少 → 负（销售退回、红冲）
  #   流出项目 + 现金减少 → 正；流出项目 + 现金增加 → 负（付款退回）
  # 无符号累加会让红冲和销售退回**另算一笔**而不是冲减原项目，
  # 一笔 1 万的红冲能把现金流量表撑成 2 万（踩过）。
  def natural_amount(item, line)
    inflow_item = Erp::CashFlowItem::BY_CODE.dig(item, :flow) == Erp::CashFlowItem::INFLOW
    debit = line.direction == Erp::VoucherLine::DEBIT
    inflow_item == debit ? line.base_amount_micros : -line.base_amount_micros
  end

  # 对方科目：优先取**反方向**里金额最大的那行（一借多贷时最能代表这笔现金的去向）。
  def counterpart_of(line, other_lines)
    opposite = other_lines.reject { |other| other.direction == line.direction }
    (opposite.presence || other_lines).max_by(&:base_amount_micros)
  end

  def build_report(from:, to:, buckets:, fx_effect:, cash_ids:)
    # 行次按《会企03表》顺次发号：每个活动「流入各行→流入小计→流出各行→流出小计→净额」，
    # 三个活动走完接 32 汇率变动、33 净增加额、34 期初、35 期末。项目顺序即报表行序。
    row_no = (1..).each
    sections = Erp::CashFlowItem::SECTIONS.keys.map { |key| section_of(key, buckets, row_no) }
    activity_net = sections.sum { |section| section[:net_micros] }
    opening, closing = cash_balances(from, to, cash_ids)
    net_increase = activity_net + fx_effect

    { from: from, to: to, sections: sections, form_code: '会企03表' }
      .merge(tail_rows(fx_effect, net_increase, opening, closing, row_no))
      .merge(variance_micros: (closing - opening) - net_increase,
             balanced: (closing - opening) == net_increase)
  end

  # 表尾四行（32-35）：汇率变动 / 净增加额 / 期初 / 期末，行次接着三个活动往下发。
  def tail_rows(fx_effect, net_increase, opening, closing, row_no)
    {
      fx_effect_micros: fx_effect, fx_effect_row_no: row_no.next,
      net_increase_micros: net_increase, net_increase_row_no: row_no.next,
      opening_cash_micros: opening, opening_row_no: row_no.next,
      closing_cash_micros: closing, closing_row_no: row_no.next
    }
  end

  def section_of(key, buckets, row_no)
    items = Erp::CashFlowItem::ITEMS.select { |item| item[:section] == key }
    inflow_rows = numbered_rows(items, buckets, Erp::CashFlowItem::INFLOW, row_no)
    inflow = { label: "#{Erp::CashFlowItem::SHORT_LABELS[key]}活动现金流入小计", row_no: row_no.next,
               amount_micros: inflow_rows.sum { |row| row[:amount_micros] } }
    outflow_rows = numbered_rows(items, buckets, Erp::CashFlowItem::OUTFLOW, row_no)
    outflow = { label: "#{Erp::CashFlowItem::SHORT_LABELS[key]}活动现金流出小计", row_no: row_no.next,
                amount_micros: outflow_rows.sum { |row| row[:amount_micros] } }

    {
      key: key, label: Erp::CashFlowItem::SECTIONS[key],
      short_label: Erp::CashFlowItem::SHORT_LABELS[key],
      rows: inflow_rows + outflow_rows,
      inflow_micros: inflow[:amount_micros], outflow_micros: outflow[:amount_micros],
      inflow_subtotal: inflow, outflow_subtotal: outflow,
      net_micros: inflow[:amount_micros] - outflow[:amount_micros],
      net_row_no: row_no.next
    }
  end

  def numbered_rows(items, buckets, flow, row_no)
    items.select { |item| item[:flow] == flow }.map do |item|
      { code: item[:code], label: item[:label], flow: item[:flow],
        row_no: row_no.next, amount_micros: buckets[item[:code]] }
    end
  end

  # 期初/期末现金（本位币）。期初＝期初前的凭证 **加上期初建账凭证**——
  # 建账凭证虽然日期落在本期内，但它是期初余额，必须算进期初、不算进流量，勾稽才成立。
  def cash_balances(from, to, cash_ids)
    base = posted_cash_lines(cash_ids)
    opening = base.where(erp_vouchers: { voucher_date: ...from })
                  .or(base.where(erp_vouchers: { source_type: OPENING_SOURCE }))
    [signed_sum(opening), signed_sum(base.where(erp_vouchers: { voucher_date: ..to }))]
  end

  def signed_sum(scope)
    sums = scope.group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::DEBIT].to_i - sums[Erp::VoucherLine::CREDIT].to_i
  end
end
