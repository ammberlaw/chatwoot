# frozen_string_literal: true

require 'rails_helper'

# 会计恒等式的看门狗。
#
# 会计系统出错是**静默的**——报表数字算错既不报错也不崩，等年审对不上才发现，
# 那时候已经错了半年账。这里只测「算钱的地方」的硬恒等式，任何一条挂了都说明账不能信。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 会计恒等式' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:cash) { account.erp_ledger_accounts.find_by(code: '1001') }
  let(:receivable) { account.erp_ledger_accounts.find_by(code: '112201') }
  let(:income) { account.erp_ledger_accounts.find_by(code: '6001') }
  let(:office) { account.erp_ledger_accounts.find_by(code: '660202') }
  let(:capital) { account.erp_ledger_accounts.find_by(code: '4001') }
  let(:customer) { create(:crm_customer, account: account) }

  let(:period_from) { Date.new(2026, 3, 1) }
  let(:period_to) { Date.new(2026, 3, 31) }

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  # 建一张已记账凭证；lines 是 [科目, 方向, 元, 额外属性] 的数组。
  def post!(summary, lines, date: Date.new(2026, 3, 10))
    voucher = account.erp_vouchers.create!(
      voucher_date: date, summary: summary, status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
      lines_attributes: lines.each_with_index.map do |(ledger, direction, yuan, extra), index|
        { ledger_account_id: ledger.id, direction: direction, amount_micros: (yuan * 1_000_000).round,
          currency: 'CNY', exchange_rate: 1, position: index }.merge(extra || {})
      end
    )
    voucher.refresh_totals!
    Erp::VoucherPostingService.new(voucher, user).post!
  end

  describe '资产负债表' do
    before do
      post!('股东投入', [[bank, 'DEBIT', 500_000], [capital, 'CREDIT', 500_000]])
      post!('确认收入', [[receivable, 'DEBIT', 80_000, { crm_customer_id: customer.id }], [income, 'CREDIT', 80_000]])
      post!('付办公费', [[office, 'DEBIT', 3_000], [bank, 'CREDIT', 3_000]])
    end

    it '资产 = 负债 + 所有者权益（含未结转的本年利润）' do
      report = Erp::FinancialReportService.new(account).balance_sheet(as_of: period_to)

      expect(report[:balanced]).to be(true)
      expect(report[:totals][:assets_micros])
        .to eq(report[:totals][:liabilities_and_equity_micros])
    end

    it '利润表净利润等于资产负债表的「本年利润（未结转）」' do
      service = Erp::FinancialReportService.new(account)
      income_statement = service.income_statement(from: period_from, to: period_to)
      balance_sheet = service.balance_sheet(as_of: period_to)

      # 收入 80,000 − 办公费 3,000 = 77,000
      expect(income_statement[:net_profit_micros]).to eq(77_000_000_000)
      expect(balance_sheet[:totals][:current_profit_micros])
        .to eq(income_statement[:net_profit_micros])
    end
  end

  describe '账簿' do
    before do
      post!('股东投入', [[bank, 'DEBIT', 500_000], [capital, 'CREDIT', 500_000]])
      post!('提现备用金', [[cash, 'DEBIT', 5_000], [bank, 'CREDIT', 5_000]])
    end

    it '末级科目借贷发生额试算平衡' do
      rows = Erp::LedgerQueryService.new(account)
                                    .balances(from: period_from, to: period_to)
                                    .reject { |row| row[:account].is_group? }

      expect(rows.sum { |row| row[:debit_micros] }).to eq(rows.sum { |row| row[:credit_micros] })
    end

    it '分类科目的数字是下级汇总上来的' do
      rows = Erp::LedgerQueryService.new(account).balances(from: period_from, to: period_to)
      by_code = rows.index_by { |row| row[:account].code }

      # 1002 银行存款（分类）= 100201 人民币户 + 100202 美元户
      expect(by_code['1002'][:closing_micros])
        .to eq(by_code['100201'][:closing_micros] + by_code['100202'][:closing_micros])
    end
  end

  describe '期末结账' do
    before do
      post!('股东投入', [[bank, 'DEBIT', 500_000], [capital, 'CREDIT', 500_000]])
      post!('确认收入', [[receivable, 'DEBIT', 80_000, { crm_customer_id: customer.id }], [income, 'CREDIT', 80_000]])
      post!('付办公费', [[office, 'DEBIT', 3_000], [bank, 'CREDIT', 3_000]])
    end

    it '结转后利润表仍按结转前口径出数（否则净利润会被冲成 0）' do
      service = Erp::FinancialReportService.new(account)
      before_close = service.income_statement(from: period_from, to: period_to)[:net_profit_micros]

      Erp::PeriodCloseService.new(account, user).close!('2026-03')

      after_close = service.income_statement(from: period_from, to: period_to)[:net_profit_micros]
      expect(after_close).to eq(before_close)
    end

    it '结转后损益科目余额被冲平，资产负债表照样平' do
      Erp::PeriodCloseService.new(account, user).close!('2026-03')
      report = Erp::FinancialReportService.new(account).balance_sheet(as_of: period_to)

      pl_rows = Erp::LedgerQueryService.new(account)
                                       .balances(from: period_from, to: period_to)
                                       .reject { |row| row[:account].is_group? }
                                       .select { |row| row[:account].category == 'PL' }

      expect(pl_rows.sum { |row| row[:closing_micros] }).to eq(0)
      expect(report[:balanced]).to be(true)
    end

    it '已结账期间的凭证被冻结' do
      Erp::PeriodCloseService.new(account, user).close!('2026-03')

      frozen = account.erp_vouchers.new(
        voucher_date: Date.new(2026, 3, 20), status: Erp::Voucher::DRAFT,
        lines_attributes: [
          { ledger_account_id: cash.id, direction: 'DEBIT', amount_micros: 1_000_000, currency: 'CNY', exchange_rate: 1 },
          { ledger_account_id: bank.id, direction: 'CREDIT', amount_micros: 1_000_000, currency: 'CNY', exchange_rate: 1 }
        ]
      )

      expect(frozen).not_to be_valid
      expect(frozen.errors.full_messages.join).to include('已结账')
    end
  end

  describe '现金流量表' do
    before do
      post!('股东投入', [[bank, 'DEBIT', 500_000], [capital, 'CREDIT', 500_000]])
      post!('收到货款', [[bank, 'DEBIT', 80_000], [receivable, 'CREDIT', 80_000, { crm_customer_id: customer.id }]])
      post!('付办公费', [[office, 'DEBIT', 3_000], [bank, 'CREDIT', 3_000]])
      post!('提现备用金', [[cash, 'DEBIT', 5_000], [bank, 'CREDIT', 5_000]])
    end

    let(:report) { Erp::CashFlowService.new(account).statement(from: period_from, to: period_to) }

    it '净增加额 = 期末现金 − 期初现金' do
      expect(report[:balanced]).to be(true)
      expect(report[:variance_micros]).to eq(0)
    end

    it '内部划转（银行→现金）不计入现金流量' do
      operating = report[:sections].find { |section| section[:key] == Erp::CashFlowItem::OPERATING }

      # 只有收货款 80,000 流入与办公费 3,000 流出；提现 5,000 两边都是货币资金，不算流量
      expect(operating[:inflow_micros]).to eq(80_000_000_000)
      expect(operating[:outflow_micros]).to eq(3_000_000_000)
    end

    it '按对方科目把收款自动归到「销售商品、提供劳务收到的现金」' do
      operating = report[:sections].find { |section| section[:key] == Erp::CashFlowItem::OPERATING }
      sales = operating[:rows].find { |row| row[:code] == 'OP_IN_SALES' }

      expect(sales[:amount_micros]).to eq(80_000_000_000)
    end

    it '分录上手工指定的现金流量项目优先于自动推断' do
      voucher = post!('收到押金', [[bank, 'DEBIT', 10_000, { cash_flow_item: 'OP_IN_OTHER' }],
                                   [receivable, 'CREDIT', 10_000, { crm_customer_id: customer.id }]])
      expect(voucher).to be_present

      operating = report[:sections].find { |section| section[:key] == Erp::CashFlowItem::OPERATING }
      other = operating[:rows].find { |row| row[:code] == 'OP_IN_OTHER' }

      expect(other[:amount_micros]).to eq(10_000_000_000)
    end
  end
end
