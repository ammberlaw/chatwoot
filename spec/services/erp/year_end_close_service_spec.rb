# frozen_string_literal: true

require 'rails_helper'

# 年末结转：本年利润 → 利润分配。
#
# 不做这一步的话「本年利润」会跨年累加——第二年起资产负债表上的本年利润里
# 混着以前年度的利润、未分配利润永远是 0。总数还是平的，是**分类**错了。
RSpec.describe Erp::YearEndCloseService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:income) { account.erp_ledger_accounts.find_by(code: '6001') }
  let(:office) { account.erp_ledger_accounts.find_by(code: '660202') }
  let(:year_profit) { account.erp_ledger_accounts.find_by(account_type: 'YEAR_PROFIT') }
  let(:retained) { account.erp_ledger_accounts.find_by(code: '4104') }
  let(:surplus) { account.erp_ledger_accounts.find_by(code: '4101') }
  let(:service) { described_class.new(account, user) }
  let(:period_service) { Erp::PeriodCloseService.new(account, user) }

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  def post!(date, debit_account, credit_account, yuan)
    voucher = account.erp_vouchers.create!(
      voucher_date: date, status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
      lines_attributes: [
        { ledger_account_id: debit_account.id, direction: 'DEBIT', amount_micros: yuan * 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 0 },
        { ledger_account_id: credit_account.id, direction: 'CREDIT', amount_micros: yuan * 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 1 }
      ]
    )
    voucher.refresh_totals!
    Erp::VoucherPostingService.new(voucher, user).post!
  end

  def balance_of(ledger_account, as_of)
    sums = account.erp_voucher_lines.joins(:voucher)
                  .where(erp_vouchers: { status: Erp::Voucher::POSTED, voucher_date: ..as_of })
                  .where(ledger_account_id: ledger_account.id).group(:direction).sum(:base_amount_micros)
    sums[Erp::VoucherLine::CREDIT].to_i - sums[Erp::VoucherLine::DEBIT].to_i
  end

  # 一个盈利年度：收入 100,000 − 办公费 30,000 = 70,000
  def build_profitable_year
    post!(Date.new(2026, 3, 10), bank, income, 100_000)
    post!(Date.new(2026, 4, 10), office, bank, 30_000)
    period_service.close!('2026-03')
    period_service.close!('2026-04')
  end

  describe '前置条件' do
    it '全年还有没结账的月份就不让年结' do
      post!(Date.new(2026, 3, 10), bank, income, 100_000)

      expect { service.run!(year: '2026') }
        .to raise_error(described_class::Error, /还没结账/)
    end

    it '本年利润为 0 时不生成空凭证' do
      post!(Date.new(2026, 3, 10), bank, account.erp_ledger_accounts.find_by(code: '4001'), 100_000)
      period_service.close!('2026-03')

      expect { service.run!(year: '2026') }.to raise_error(described_class::Error, /为 0/)
    end

    it '同一年度不能年结两次' do
      build_profitable_year
      service.run!(year: '2026')

      expect { service.run!(year: '2026') }.to raise_error(described_class::Error, /已经年结过/)
    end
  end

  describe '盈利年度' do
    before { build_profitable_year }

    it '本年利润结平，全额转入利润分配' do
      result = service.run!(year: '2026')
      as_of = Date.new(2026, 12, 31)

      expect(result[:profit_micros]).to eq(70_000_000_000)
      expect(balance_of(year_profit, as_of)).to eq(0)
      expect(balance_of(retained, as_of)).to eq(70_000_000_000)
    end

    it '年结不改变资产负债表的平衡' do
      service.run!(year: '2026')
      report = Erp::FinancialReportService.new(account).balance_sheet(as_of: Date.new(2026, 12, 31))

      expect(report[:balanced]).to be(true)
    end

    it '填了比例才提法定盈余公积' do
      result = service.run!(year: '2026', surplus_rate: 10)
      as_of = Date.new(2026, 12, 31)

      expect(result[:surplus_micros]).to eq(7_000_000_000)
      expect(balance_of(surplus, as_of)).to eq(7_000_000_000)
      expect(balance_of(retained, as_of)).to eq(63_000_000_000)
    end

    it '默认不提盈余公积' do
      service.run!(year: '2026')

      expect(balance_of(surplus, Date.new(2026, 12, 31))).to eq(0)
    end
  end

  describe '亏损年度' do
    before do
      post!(Date.new(2026, 3, 10), office, bank, 20_000)
      period_service.close!('2026-03')
    end

    it '亏损转入利润分配（借方），且不提盈余公积' do
      result = service.run!(year: '2026', surplus_rate: 10)
      as_of = Date.new(2026, 12, 31)

      expect(result[:profit_micros]).to eq(-20_000_000_000)
      expect(result[:surplus_micros]).to eq(0)
      expect(balance_of(year_profit, as_of)).to eq(0)
      expect(balance_of(retained, as_of)).to eq(-20_000_000_000)
    end
  end

  describe '反年结' do
    before { build_profitable_year }

    it '撤销后本年利润回到年结前，可以重做' do
      service.run!(year: '2026')
      service.reopen!(year: '2026')
      as_of = Date.new(2026, 12, 31)

      expect(balance_of(year_profit, as_of)).to eq(70_000_000_000)
      expect(balance_of(retained, as_of)).to eq(0)
      expect { service.run!(year: '2026') }.not_to raise_error
    end

    it '年结之后不让反结该年度的月份（要先反年结）' do
      service.run!(year: '2026')

      expect { period_service.reopen!('2026-04') }
        .to raise_error(Erp::PeriodCloseService::Error, /先反年结/)
    end

    it '反年结之后就能正常反结月份了' do
      service.run!(year: '2026')
      service.reopen!(year: '2026')

      expect { period_service.reopen!('2026-04') }.not_to raise_error
    end
  end
end
