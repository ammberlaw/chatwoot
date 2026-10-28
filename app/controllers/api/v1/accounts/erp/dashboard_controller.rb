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
      # 开账体检：没建会计期间 / 没录期初 / 订单没建台账 / 凭证没过账时，报表是空的
      # 而系统一切「正常」。缺哪件摆在看板上，别等月底才发现。
      readiness: Erp::OpeningReadiness.new(account).call,
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
      cash_foreign: cash_foreign,
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

  # 已收款按到期日 FIFO 先冲最早的分期（与账龄分析同口径）：
  # 订金早收了、尾款没到期，逾期不能把整期订金再算一遍——否则看板逾期与账龄页两个数对不上，且虚高。
  # 返回 [[installment, 未收余额], ...]，已被收款盖住的分期直接不出现。
  def overdue_rows
    @overdue_rows ||= begin
      received_left = {}
      overdue_scope.includes(receivable: [:crm_customer, :owner]).order(:due_date).filter_map do |installment|
        receivable = installment.receivable
        left = received_left.fetch(receivable.id) { receivable.received_amount_micros.to_i }
        covered = [left, installment.amount_micros].min
        received_left[receivable.id] = left - covered
        outstanding = installment.amount_micros - covered
        [installment, outstanding] if outstanding.positive?
      end
    end
  end

  # 分期表本身没有币种列，币种跟着所属台账走，所以按台账的汇率折。
  def overdue_amount
    overdue_rows.sum { |installment, outstanding| (outstanding * (installment.receivable.exchange_rate.presence || 1).to_d).round }
  end

  def overdue_installments
    overdue_rows.first(10).map do |installment, outstanding|
      receivable = installment.receivable
      {
        id: installment.id, receivable_no: receivable.receivable_no,
        customer_name: receivable.crm_customer&.name,
        owner_name: receivable.owner&.name.presence || receivable.owner&.crm_name,
        kind_label: Erp::ReceivableInstallment::KIND_LABELS[installment.kind],
        amount_micros: outstanding, due_date: installment.due_date,
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

  # 只加本位币账户——直接把 USD/EUR 余额 1:1 加进人民币 KPI 就是错数。
  # 外币账户按币种单列（cash_foreign），前端在卡片下方标注，不折算（流水没有逐笔汇率快照可用）。
  def cash_balance
    account.erp_cash_accounts.active.select { |row| row.currency == 'CNY' }.sum(&:balance_micros)
  end

  def cash_foreign
    account.erp_cash_accounts.active.reject { |row| row.currency == 'CNY' }
           .group_by(&:currency)
           .map { |currency, rows| { currency: currency, amount_micros: rows.sum(&:balance_micros) } }
           .sort_by { |row| row[:currency] }
  end

  def month_profit
    Erp::FinancialReportService.new(account)
                               .income_statement(from: month_range.first, to: month_range.last, comparative: false)[:net_profit_micros]
  end
end
