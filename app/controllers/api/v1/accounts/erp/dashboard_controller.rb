# 财务看板：真实数据（不放假数字——没数据就是 0）。
# 口径：回款/付款按单据日期取本月正常单据；余额取台账未结；资金按账户余额折本位币；
# 利润走利润表口径（排除期末结转凭证）。
class Api::V1::Accounts::Erp::DashboardController < Api::V1::Accounts::Erp::BaseController
  DUE_SOON_DAYS = 7

  def show
    render json: {
      kpis: kpis,
      overdue_installments: overdue_installments,
      pending_vouchers: pending_vouchers,
      capabilities: Current.account_user&.erp_capability_list || []
    }
  end

  private

  def account
    Current.account
  end

  def kpis
    {
      month_receipt: month_sum(account.erp_receipt_records.normal.where(received_at: month_range),
                               Erp::ReceiptRecord::BASE_AMOUNT_MICROS_SQL),
      month_payment: month_sum(account.erp_payment_records.normal.where(paid_at: month_range),
                               Erp::PaymentRecord::BASE_AMOUNT_MICROS_SQL),
      overdue_receivable: overdue_amount,
      cash_balance: cash_balance,
      month_profit: month_profit,
      draft_voucher_count: account.erp_vouchers.where(status: Erp::Voucher::DRAFT).count
    }.merge(ledger_balances)
  end

  def ledger_balances
    {
      receivable_balance: outstanding(account.erp_receivables, Erp::Receivable::BASE_TOTAL_MICROS_SQL,
                                      Erp::Receivable::BASE_RECEIVED_MICROS_SQL),
      payable_balance: outstanding(account.erp_payables, Erp::Payable::BASE_TOTAL_MICROS_SQL,
                                   Erp::Payable::BASE_PAID_MICROS_SQL)
    }
  end

  def month_sum(scope, sql)
    scope.sum(Arel.sql(sql))
  end

  def month_range
    Time.zone.today.all_month
  end

  # 看板是全公司口径，外币必须折本位币再加——直接 sum 原币等于把美元当人民币 1:1 算。
  def outstanding(scope, total_sql, paid_sql)
    scope.sum(Arel.sql(total_sql)) - scope.sum(Arel.sql(paid_sql))
  end

  # 逾期应收：到期日已过、且所属台账还没收清的分期金额。
  def overdue_scope
    account.erp_receivable_installments
           .joins(:receivable)
           .where(erp_receivables: { status: [Erp::Receivable::UNPAID, Erp::Receivable::PARTIAL] })
           .where(due_date: ...Time.zone.today)
  end

  # 分期表本身没有币种列，币种跟着所属台账走，所以按台账的汇率折。
  def overdue_amount
    overdue_scope.sum(Arel.sql('ROUND(erp_receivable_installments.amount_micros * COALESCE(erp_receivables.exchange_rate, 1))'))
  end

  def overdue_installments
    overdue_scope.includes(receivable: [:crm_customer, :owner]).order(:due_date).limit(10).map do |installment|
      receivable = installment.receivable
      {
        id: installment.id, receivable_no: receivable.receivable_no,
        customer_name: receivable.crm_customer&.name,
        owner_name: receivable.owner&.crm_name.presence || receivable.owner&.name,
        kind_label: Erp::ReceivableInstallment::KIND_LABELS[installment.kind],
        amount_micros: installment.amount_micros, due_date: installment.due_date,
        overdue_days: (Time.zone.today - installment.due_date).to_i
      }
    end
  end

  # 待过账凭证队列（自动凭证进来的都在这），看板直接看到「有几张等着审」。
  def pending_vouchers
    account.erp_vouchers.where(status: Erp::Voucher::DRAFT).order(voucher_date: :desc).limit(8).map do |voucher|
      {
        id: voucher.id, voucher_no: voucher.voucher_no, voucher_date: voucher.voucher_date,
        summary: voucher.summary, total_debit_micros: voucher.total_debit_micros,
        balanced: voucher.balanced?, source_type: voucher.source_type
      }
    end
  end

  def cash_balance
    account.erp_cash_accounts.active.sum(&:balance_micros)
  end

  def month_profit
    Erp::FinancialReportService.new(account)
                               .income_statement(from: month_range.first, to: month_range.last)[:net_profit_micros]
  end
end
