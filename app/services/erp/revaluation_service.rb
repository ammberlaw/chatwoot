# 期末调汇：外币科目按期末汇率重算本位币，差额进「汇兑损益」。
#
# 算法（每个外币末级科目、往来科目再按单位拆）：
#   期末应有本位币 = 原币余额 × 期末汇率
#   调汇差额       = 应有本位币 − 账面本位币（账面是历史各笔按当时汇率折出来的和）
# 差额为正就借记该科目、为负就贷记，全部差额的净额记到汇兑损益的另一边。
#
# 两个要点：
# 1. **调汇只动本位币、不动原币**——分录的原币金额是 0，本位币是差额。这是准则口径，
#    也是金蝶调汇凭证的样子；`Erp::VoucherLine` 为此放行了原币 0（本位币仍必须为正）。
# 2. **往来科目必须按单位逐个调**：应收/应付挂了客户/供应商必填维度，一条汇总分录既进不去、
#    也会让「这个客户欠多少」在调汇后对不上。
#
# 幂等：调完汇账面就等于应有，同样汇率再跑一次差额自然是 0，不会重复生成；
# 该期间已有未过账的调汇凭证则整张替换（跟期初建账一个做法）。
class Erp::RevaluationService
  class Error < StandardError; end

  SOURCE_TYPE = 'Erp::Revaluation'.freeze
  BASE_CURRENCY = 'CNY'.freeze

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 预览：不落库，返回每个科目/单位的原币余额、账面本位币、应有本位币与差额。
  # 汇率还没填全时只回币种清单（页面靠它渲染汇率输入框），不硬算出一堆假差额。
  def preview(period:, rates:)
    as_of = period_end(period)
    return empty_preview(period, as_of, rates) if missing_rates(rates).any?

    lines = foreign_accounts.flat_map { |ledger_account| account_rows(ledger_account, as_of, rates) }
    { period: period, as_of: as_of, rates: rates, rows: lines, rates_ready: true,
      total_diff_micros: lines.sum { |row| row[:diff_micros] }, currencies: currencies }
  end

  # 生成调汇凭证（待过账）。没有差额就不生成空凭证，返回 voucher_no: nil。
  def run!(period:, rates:)
    validate!(period, rates)
    result = preview(period: period, rates: rates)
    rows = result[:rows].reject { |row| row[:diff_micros].zero? }

    ActiveRecord::Base.transaction do
      discard_draft!(period)
      voucher = rows.empty? ? nil : build_voucher(result, rows)
      result.merge(voucher_no: voucher&.voucher_no, count: rows.size)
    end
  end

  # 账套里用到的外币（给页面渲染汇率输入框）。
  def currencies
    foreign_accounts.map(&:currency).uniq.sort
  end

  private

  def foreign_accounts
    @foreign_accounts ||= @account.erp_ledger_accounts.active.leaves
                                  .where.not(currency: [nil, '', BASE_CURRENCY]).order(:code).to_a
  end

  def period_end(period)
    raise Error, '会计期间格式应为 YYYY-MM' unless period.to_s.match?(/\A\d{4}-\d{2}\z/)

    Date.parse("#{period}-01").end_of_month
  end

  def empty_preview(period, as_of, rates)
    { period: period, as_of: as_of, rates: rates, rows: [], rates_ready: false,
      total_diff_micros: 0, currencies: currencies }
  end

  def missing_rates(rates)
    currencies.reject { |currency| rates[currency].to_d.positive? }
  end

  def validate!(period, rates)
    period_end(period)
    raise Error, '账套里没有外币科目，不需要调汇' if currencies.empty?
    raise Error, "会计期间 #{period} 已结账，不能再调汇" if Erp::FiscalPeriod.closed?(@account, period)

    missing = missing_rates(rates)
    raise Error, "还没填 #{missing.join('、')} 的期末汇率" if missing.any?
  end

  # 一个外币科目的调汇行：往来科目按单位拆，其余整个科目一行。
  def account_rows(ledger_account, as_of, rates)
    rate = rates[ledger_account.currency].to_d
    dimension = ledger_account.required_dimension
    balances(ledger_account, as_of, dimension).map do |party_id, sums|
      build_row(ledger_account, rate, dimension, party_id, sums)
    end
  end

  def build_row(ledger_account, rate, dimension, party_id, sums)
    should_be = (sums[:original] * rate).round
    {
      ledger_account_id: ledger_account.id, code: ledger_account.code, name: ledger_account.name,
      currency: ledger_account.currency, rate: rate,
      dimension: dimension, party_id: party_id, party_name: party_name(dimension, party_id),
      original_micros: sums[:original], booked_micros: sums[:booked],
      should_be_micros: should_be, diff_micros: should_be - sums[:booked]
    }
  end

  # 返回 { 单位id(或 nil) => { original: 原币余额, booked: 账面本位币余额 } }。
  def balances(ledger_account, as_of, dimension)
    scope = @account.erp_voucher_lines.joins(:voucher)
                    .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: ..as_of })
                    .where(ledger_account_id: ledger_account.id)
    key = dimension.present? ? Erp::LedgerQueryService::DIMENSION_COLUMNS[dimension] : nil
    grouped = key ? scope.group(key, :direction) : scope.group(:direction)
    signed(grouped.sum(:amount_micros), grouped.sum(:base_amount_micros), key)
  end

  def signed(original_sums, base_sums, key)
    parties = key ? original_sums.keys.map(&:first).uniq : [nil]
    parties.index_with do |party|
      { original: net(original_sums, party, key), booked: net(base_sums, party, key) }
    end
  end

  def net(sums, party, key)
    debit_key = key ? [party, Erp::VoucherLine::DEBIT] : Erp::VoucherLine::DEBIT
    credit_key = key ? [party, Erp::VoucherLine::CREDIT] : Erp::VoucherLine::CREDIT
    sums[debit_key].to_i - sums[credit_key].to_i
  end

  def party_name(dimension, party_id)
    return nil if dimension.blank? || party_id.blank?

    case dimension
    when 'customer' then @account.crm_customers.find_by(id: party_id)&.name
    when 'supplier' then @account.mes_suppliers.find_by(id: party_id)&.name
    end
  end

  # 同期间的未过账调汇凭证整张作废重来；已过账的不动（要改得红冲）。
  def discard_draft!(period)
    @account.erp_vouchers.where(source_type: SOURCE_TYPE, period: period, status: Erp::Voucher::DRAFT)
            .destroy_all
  end

  def build_voucher(result, rows)
    voucher = @account.erp_vouchers.create!(
      voucher_date: result[:as_of], period: result[:period], status: Erp::Voucher::DRAFT,
      summary: "#{result[:period]} 期末调汇（#{rate_note(result[:rates])}）",
      prepared_by_id: @user&.id, source_type: SOURCE_TYPE,
      lines_attributes: voucher_lines(rows).each_with_index.map { |line, index| line.merge(position: index) }
    )
    voucher.refresh_totals!
    voucher
  end

  def voucher_lines(rows)
    diff_account = @account.erp_ledger_accounts.active.leaves.find_by(account_type: 'EXCHANGE_DIFF')
    raise Error, '找不到「汇兑损益」科目，请先在科目表里配置' if diff_account.blank?

    total = rows.sum { |row| row[:diff_micros] }
    lines = rows.map { |row| revaluation_line(row) }
    # 各科目差额正负相抵、净额恰好为 0 时，调汇行自己已经借贷平了，不能再挂一条 0 元损益行。
    total.zero? ? lines : lines + [diff_line(diff_account, total)]
  end

  def rate_note(rates)
    currencies.map { |currency| "#{currency} #{format('%.4f', rates[currency].to_d)}" }.join('、')
  end

  # 原币 0、本位币＝差额；差额为正调增借方，为负调增贷方。
  def revaluation_line(row)
    line = {
      ledger_account_id: row[:ledger_account_id],
      direction: row[:diff_micros].positive? ? Erp::VoucherLine::DEBIT : Erp::VoucherLine::CREDIT,
      amount_micros: 0, base_amount_micros: row[:diff_micros].abs,
      currency: row[:currency], exchange_rate: row[:rate],
      summary: "期末调汇 #{row[:currency]} #{format('%.4f', row[:rate])}"
    }
    column = Erp::LedgerQueryService::DIMENSION_COLUMNS[row[:dimension]]
    column ? line.merge(column => row[:party_id]) : line
  end

  # 净差额进汇兑损益：外币资产净升值＝收益记贷方，净贬值＝损失记借方。
  def diff_line(diff_account, total)
    {
      ledger_account_id: diff_account.id,
      direction: total.positive? ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT,
      amount_micros: total.abs, base_amount_micros: total.abs,
      currency: BASE_CURRENCY, exchange_rate: 1, summary: '期末调汇差额'
    }
  end
end
