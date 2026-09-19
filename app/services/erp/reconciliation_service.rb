# 两账对平（ERP_SPEC §9.4）：业务台账 vs 会计总账，每月结账前必须零差异。
#
# 对三组：
#   应收台账未收合计  vs  应收账款科目余额
#   应付台账未付合计  vs  应付账款科目余额
#   资金账户余额合计  vs  货币资金科目余额
# 有差异通常是「单据没生成凭证」或「凭证记错科目」，页面直接把差额摆出来。
class Erp::ReconciliationService
  GROUPS = [
    { key: 'receivable', label: '应收', account_type: 'RECEIVABLE' },
    { key: 'payable', label: '应付', account_type: 'PAYABLE' },
    { key: 'cash', label: '资金', account_type: %w[CASH BANK] }
  ].freeze

  def initialize(account)
    @account = account
  end

  def call(as_of: Time.zone.today)
    balances = Erp::LedgerQueryService.new(@account).balances(from: Erp::FinancialReportService::EPOCH, to: as_of)
    GROUPS.map { |group| row_for(group, balances) }
  end

  private

  def row_for(group, balances)
    ledger = ledger_balance(group[:account_type], balances)
    business = business_balance(group[:key])
    { key: group[:key], label: group[:label], business_micros: business, ledger_micros: ledger,
      diff_micros: business - ledger, matched: business == ledger, note: note_for(group[:key]) }
  end

  # 外币的本位币余额只能由凭证（按录入时汇率折算）决定，与台账/账户原币余额不可比，
  # 所以三组都只对本位币，外币的量单独提示、按外币另行核对——没有提示的排除项等于「假绿灯」。
  def note_for(key)
    count = case key
            when 'cash' then @account.erp_cash_accounts.active.where.not(currency: 'CNY').count
            when 'receivable' then @account.erp_receivables.where.not(currency: 'CNY').count
            else @account.erp_payables.where.not(currency: 'CNY').count
            end
    return nil if count.zero?

    unit = key == 'cash' ? '个外币账户' : '条外币台账'
    "另有 #{count} #{unit}未纳入本位币对平，请按外币单独核对"
  end

  # 总账侧取本位币科目：currency 为空＝本位币；财务把科目显式标成 CNY 也算——
  # 自动凭证选科目时优先币种精确匹配，标了 CNY 的科目会实际入账，从对平里剔掉就是一笔解释不了的永久差额。
  def ledger_balance(types, balances)
    wanted = Array(types)
    balances.reject { |row| row[:account].is_group? }
            .select { |row| wanted.include?(row[:account].account_type) }
            .select { |row| row[:account].currency.blank? || row[:account].currency == 'CNY' }
            .sum { |row| row[:closing_micros] }
  end

  def business_balance(key)
    case key
    when 'receivable'
      # 只取本位币台账：总账侧取的也是本位币科目（currency 为空的），外币台账原币与之不可比。
      cny = @account.erp_receivables.where(currency: 'CNY')
      cny.sum(:total_amount_micros) - cny.sum(:received_amount_micros)
    when 'payable'
      cny = @account.erp_payables.where(currency: 'CNY')
      cny.sum(:total_amount_micros) - cny.sum(:paid_amount_micros)
    else
      @account.erp_cash_accounts.active.where(currency: 'CNY').sum(&:balance_micros)
    end
  end
end
