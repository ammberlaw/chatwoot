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

  # 外币账户的本位币余额只能由凭证（按录入时汇率折算）决定，账户上的原币余额不能直接和总账比，
  # 所以资金对平只对本位币账户，外币账户单独提示、按外币另行核对。
  def note_for(key)
    return nil unless key == 'cash'

    foreign = @account.erp_cash_accounts.active.where.not(currency: 'CNY').count
    foreign.zero? ? nil : "另有 #{foreign} 个外币账户未纳入本位币对平，请按外币单独核对"
  end

  # 总账侧同样只取本位币科目——外币科目余额是本位币折算数，与外币账户原币不可比。
  def ledger_balance(types, balances)
    wanted = Array(types)
    balances.reject { |row| row[:account].is_group? }
            .select { |row| wanted.include?(row[:account].account_type) && row[:account].currency.blank? }
            .sum { |row| row[:closing_micros] }
  end

  def business_balance(key)
    case key
    when 'receivable'
      @account.erp_receivables.sum(:total_amount_micros) - @account.erp_receivables.sum(:received_amount_micros)
    when 'payable'
      @account.erp_payables.sum(:total_amount_micros) - @account.erp_payables.sum(:paid_amount_micros)
    else
      @account.erp_cash_accounts.active.where(currency: 'CNY').sum(&:balance_micros)
    end
  end
end
