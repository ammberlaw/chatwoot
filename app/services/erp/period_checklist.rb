# 结账前的期末事项清单：调汇 / 折旧 / 坏账。
#
# **只提示、不硬拦**——这几项做不做是会计政策（比如坏账未必月月提），系统不该替财务决定。
# 但不提示的话，结完账才想起来没调汇就得反结账重来，所以摆在结账按钮旁边。
# 只对未结账期间算；已结账的期间没什么可做的了。
class Erp::PeriodChecklist
  ITEMS = [
    { key: 'revaluation', label: '期末调汇', source: 'Erp::Revaluation', hint: '有外币余额，本期还没调汇' },
    { key: 'depreciation', label: '计提折旧', source: 'Erp::Depreciation', hint: '有在用固定资产，本期还没计提折旧' },
    { key: 'bad_debt', label: '计提坏账', source: 'Erp::BadDebt', hint: '有未结应收，本期还没计提坏账' }
  ].freeze

  def initialize(account)
    @account = account
  end

  def for(period)
    done = done_sources(period)
    ITEMS.filter_map do |item|
      next unless applicable?(item[:key], period)

      { key: item[:key], label: item[:label], done: done.include?(item[:source]), hint: item[:hint] }
    end
  end

  private

  # 该期间已生成并记账的期末事项凭证来源。
  def done_sources(period)
    @account.erp_vouchers.in_period(period).where(status: Erp::Voucher::POSTED)
            .distinct.pluck(:source_type).compact.to_set
  end

  def applicable?(key, period)
    case key
    when 'revaluation' then foreign_balance?(period)
    when 'depreciation' then @account.erp_fixed_assets.in_use.exists?(purchased_at: ..period_end(period))
    when 'bad_debt' then @account.erp_receivables.open.exists?
    end
  end

  # 截至期末还有外币原币余额的科目才需要调汇。
  def foreign_balance?(period)
    ids = @account.erp_ledger_accounts.active.leaves.where.not(currency: [nil, '', 'CNY']).pluck(:id)
    return false if ids.empty?

    sums = @account.erp_voucher_lines.joins(:voucher)
                   .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: ..period_end(period) })
                   .where(ledger_account_id: ids).group(:direction).sum(:amount_micros)
    sums[Erp::VoucherLine::DEBIT].to_i != sums[Erp::VoucherLine::CREDIT].to_i
  end

  def period_end(period)
    Date.parse("#{period}-01").end_of_month
  end
end
