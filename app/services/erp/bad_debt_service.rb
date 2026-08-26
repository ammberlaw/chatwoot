# 坏账准备计提（账龄分析法）。
#
# 口径：按**建账日**账龄（不是逾期账龄）把应收未结余额分段，各段乘计提比例，
# 加总得到「期末应有的坏账准备余额」；跟坏账准备科目当前余额比，只补差额。
#
# 关键：坏账准备是**余额科目**，不是每期重新提一遍。
#   计提额 = 应有余额 − 已提余额
# 差额为正就计提（借 资产减值损失 / 贷 坏账准备），为负就**转回**（反向分录）。
# 这样同一比例重复跑不会翻倍，账龄变化时也能自动补提或冲回。
class Erp::BadDebtService
  class Error < StandardError; end

  SOURCE_TYPE = 'Erp::BadDebt'.freeze
  ALLOWANCE_CODE = '1231'.freeze   # 坏账准备（备抵，贷方）
  IMPAIRMENT_CODE = '6701'.freeze  # 资产减值损失

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 预览：按客户 × 账龄段列出计提基数与计提额，不落库。
  def preview(period:, rates: nil)
    as_of = period_end(period)
    table = rate_table(rates)
    aging = Erp::AgingService.new(@account).receivables(as_of: as_of, basis: Erp::AgingService::INVOICE)
    rows = aging[:rows].map { |row| customer_row(row, aging[:buckets], table) }
    build_report(period, as_of, table, aging[:buckets], rows)
  end

  # 生成计提/转回凭证（待过账）。差额为 0 就不生成空凭证。
  def run!(period:, rates: nil)
    raise Error, "会计期间 #{period} 已结账，不能再计提坏账" if Erp::FiscalPeriod.closed?(@account, period)

    result = preview(period: period, rates: rates)
    ActiveRecord::Base.transaction do
      discard_draft!(period)
      voucher = result[:adjustment_micros].zero? ? nil : build_voucher(result)
      result.merge(voucher_no: voucher&.voucher_no)
    end
  end

  # 保存计提比例（账套级政策）。
  def save_rates!(rates)
    setting = Erp::Setting.for_account(@account)
    setting.bad_debt_rates = normalize(rates)
    setting.save!
    setting.bad_debt_rate_table
  end

  private

  def period_end(period)
    raise Error, '会计期间格式应为 YYYY-MM' unless period.to_s.match?(/\A\d{4}-\d{2}\z/)

    Date.parse("#{period}-01").end_of_month
  end

  def rate_table(rates)
    rates.present? ? Erp::Setting::DEFAULT_BAD_DEBT_RATES.merge(normalize(rates)) : Erp::Setting.for_account(@account).bad_debt_rate_table
  end

  def normalize(rates)
    rates.to_h.slice(*Erp::Setting::DEFAULT_BAD_DEBT_RATES.keys).transform_values(&:to_d)
  end

  def customer_row(row, buckets, table)
    cells = buckets.to_h do |bucket|
      base = row[:cells][bucket[:key]].to_i
      [bucket[:key], { base_micros: base, rate: table[bucket[:key]].to_d, provision_micros: provision(base, table[bucket[:key]]) }]
    end
    {
      party_id: row[:party_id], party_name: row[:party_name], total_micros: row[:total_micros],
      cells: cells, provision_micros: cells.values.sum { |cell| cell[:provision_micros] }
    }
  end

  def provision(base_micros, rate)
    (base_micros * rate.to_d / 100).round
  end

  def build_report(period, as_of, table, buckets, rows)
    required = rows.sum { |row| row[:provision_micros] }
    booked = allowance_balance(as_of)
    {
      period: period, as_of: as_of, rates: table, buckets: buckets, rows: rows,
      receivable_micros: rows.sum { |row| row[:total_micros] },
      required_micros: required, booked_micros: booked, adjustment_micros: required - booked
    }
  end

  # 坏账准备科目当前余额（贷方为正）。
  def allowance_balance(as_of)
    allowance = find_account!(ALLOWANCE_CODE, '坏账准备')
    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: ..as_of })
                   .where(ledger_account_id: allowance.id)
                   .group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::CREDIT].to_i - sums[Erp::VoucherLine::DEBIT].to_i
  end

  def find_account!(code, label)
    @account.erp_ledger_accounts.active.leaves.find_by(code: code) ||
      raise(Error, "找不到「#{label}」科目（#{code}），请先在科目表里配置")
  end

  def discard_draft!(period)
    @account.erp_vouchers.where(source_type: SOURCE_TYPE, period: period, status: Erp::Voucher::DRAFT).destroy_all
  end

  def build_voucher(result)
    allowance = find_account!(ALLOWANCE_CODE, '坏账准备')
    impairment = find_account!(IMPAIRMENT_CODE, '资产减值损失')
    amount = result[:adjustment_micros]
    topping_up = amount.positive?
    summary = "#{result[:period]} #{topping_up ? '计提' : '转回'}坏账准备（账龄分析法）"

    voucher = @account.erp_vouchers.create!(
      voucher_date: result[:as_of], period: result[:period], status: Erp::Voucher::DRAFT,
      summary: summary, prepared_by_id: @user&.id, source_type: SOURCE_TYPE,
      lines_attributes: [
        line(impairment, topping_up ? Erp::VoucherLine::DEBIT : Erp::VoucherLine::CREDIT, amount.abs, summary, 0),
        line(allowance, topping_up ? Erp::VoucherLine::CREDIT : Erp::VoucherLine::DEBIT, amount.abs, summary, 1)
      ]
    )
    voucher.refresh_totals!
    voucher
  end

  def line(ledger_account, direction, amount_micros, summary, position)
    { ledger_account_id: ledger_account.id, direction: direction, amount_micros: amount_micros,
      summary: summary, currency: 'CNY', exchange_rate: 1, position: position }
  end
end
