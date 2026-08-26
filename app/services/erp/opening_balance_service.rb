# 期初建账：启用账套时把各科目的期初余额录进来。
#
# 做法：生成一张**特殊凭证**（source_type=Erp::OpeningBalance，日期＝启用日前一天，直接已记账），
# 这样账簿/报表不需要任何特判——期初就是一张凭证，余额表的「期初」自然带出来。
# 重录就是整张替换；借贷必平才让保存（期初不平说明账没理清，不能放进来）。
class Erp::OpeningBalanceService
  class Error < StandardError; end

  SOURCE_TYPE = 'Erp::OpeningBalance'.freeze

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  def current
    @account.erp_vouchers.where(source_type: SOURCE_TYPE).where.not(status: Erp::Voucher::VOID)
            .includes(lines: :ledger_account).order(:id).last
  end

  # rows: [{ ledger_account_id:, debit_micros:, credit_micros: }]
  def save!(rows:, as_of:)
    lines = normalize(rows)
    raise Error, '期初余额一条都没填' if lines.empty?

    validate_balanced!(lines)
    ActiveRecord::Base.transaction do
      current&.destroy
      build_voucher(lines, as_of)
    end
  end

  private

  # 币种跟随科目（外币科目必须按外币录，否则分录行的币种校验会拦）；
  # 外币行按填的汇率折本位币，平衡校验用本位币金额。
  def normalize(rows)
    accounts = @account.erp_ledger_accounts.where(id: Array(rows).map { |row| row[:ledger_account_id] }).index_by(&:id)
    Array(rows).filter_map { |row| normalize_row(row, accounts) }
  end

  def normalize_row(row, accounts)
    debit = row[:debit_micros].to_i
    credit = row[:credit_micros].to_i
    return if debit.zero? && credit.zero?

    ledger = accounts[row[:ledger_account_id].to_i]
    rate = row[:exchange_rate].presence || 1
    {
      ledger_account_id: row[:ledger_account_id].to_i,
      direction: debit.positive? ? Erp::VoucherLine::DEBIT : Erp::VoucherLine::CREDIT,
      amount_micros: debit.positive? ? debit : credit,
      summary: '期初余额', currency: ledger&.currency.presence || 'CNY', exchange_rate: rate
    }
  end

  def validate_balanced!(lines)
    debit = base_total(lines, Erp::VoucherLine::DEBIT)
    credit = base_total(lines, Erp::VoucherLine::CREDIT)
    return if debit == credit

    raise Error, "期初借贷不平（本位币 借 #{fmt(debit)} / 贷 #{fmt(credit)}），差额 #{fmt((debit - credit).abs)}"
  end

  def base_total(lines, direction)
    lines.select { |row| row[:direction] == direction }
         .sum { |row| (row[:amount_micros] * row[:exchange_rate].to_d).round }
  end

  def build_voucher(lines, as_of)
    date = as_of.to_date
    voucher = @account.erp_vouchers.new(
      voucher_date: date, summary: "期初建账（截至 #{date}）", status: Erp::Voucher::POSTED,
      prepared_by_id: @user&.id, posted_by_id: @user&.id, posted_at: Time.current, source_type: SOURCE_TYPE,
      lines_attributes: lines.each_with_index.map { |row, index| row.merge(position: index) }
    )
    voucher.skip_period_guard = true
    voucher.save!
    voucher.refresh_totals!
    voucher
  end

  def fmt(micros)
    format('%.2f', micros.to_i / 1_000_000.0)
  end
end
