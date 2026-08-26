# frozen_string_literal: true

require 'rails_helper'

# 跨单据联动：收付款单 ↔ 台账 ↔ 资金流水 ↔ 自动凭证 ↔ 红冲。
#
# 单点逻辑各自都对，链路上却容易在「改单 / 作废 / 红冲」这几个动作上脱节——
# 而脱节的表现是**总账与台账悄悄不平**，没有任何报错。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 跨单据联动' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }

  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:income) { account.erp_ledger_accounts.find_by(code: '6001') }
  let(:cash_account) do
    account.erp_cash_accounts.create!(name: '基本户', kind: 'BANK', currency: 'CNY',
                                      ledger_account_id: bank.id)
  end

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  describe '红冲' do
    it '红冲分录要带上原分录的现金流量项目，否则现金流量表两条不抵消' do
      voucher = account.erp_vouchers.create!(
        voucher_date: Time.zone.today, summary: '收押金', status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
        lines_attributes: [
          { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: 10_000_000_000,
            currency: 'CNY', exchange_rate: 1, cash_flow_item: 'FIN_IN_OTHER', position: 0 },
          { ledger_account_id: income.id, direction: 'CREDIT', amount_micros: 10_000_000_000,
            currency: 'CNY', exchange_rate: 1, position: 1 }
        ]
      )
      voucher.refresh_totals!
      Erp::VoucherPostingService.new(voucher, user).post!

      reversal = Erp::VoucherPostingService.new(voucher.reload, user).reverse!
      reversed_cash_line = reversal.lines.find { |line| line.ledger_account_id == bank.id }

      expect(reversed_cash_line.cash_flow_item).to eq('FIN_IN_OTHER')
    end

    it '红冲后该笔在现金流量表上净额归零' do
      voucher = account.erp_vouchers.create!(
        voucher_date: Time.zone.today, summary: '收押金', status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
        lines_attributes: [
          { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: 10_000_000_000,
            currency: 'CNY', exchange_rate: 1, cash_flow_item: 'FIN_IN_OTHER', position: 0 },
          { ledger_account_id: income.id, direction: 'CREDIT', amount_micros: 10_000_000_000,
            currency: 'CNY', exchange_rate: 1, position: 1 }
        ]
      )
      voucher.refresh_totals!
      Erp::VoucherPostingService.new(voucher, user).post!
      Erp::VoucherPostingService.new(voucher.reload, user).reverse!

      report = Erp::CashFlowService.new(account)
                                   .statement(from: Time.zone.today.beginning_of_month, to: Time.zone.today.end_of_month)
      amounts = report[:sections].flat_map { |section| section[:rows] }.pluck(:amount_micros)

      expect(amounts.sum).to eq(0)
    end
  end

  describe '收款单改单' do
    let(:receipt) do
      account.erp_receipt_records.create!(
        crm_customer_id: customer.id, received_at: Time.zone.today, amount_micros: 5_000_000_000,
        currency: 'CNY', exchange_rate: 1, cash_account_id: cash_account.id, recorded_by_id: user.id
      )
    end

    def sync!
      Erp::CashLedgerService.new(account, user).sync_for(receipt, direction: Erp::CashTransaction::IN)
    end

    def flow_net
      account.erp_cash_transactions.where(source_type: 'Erp::ReceiptRecord', source_id: receipt.id)
             .sum { |row| row.direction == Erp::CashTransaction::IN ? row.amount_micros : -row.amount_micros }
    end

    it '改金额后资金流水净额跟着变，不累加' do
      sync!
      receipt.update!(amount_micros: 3_000_000_000)
      sync!

      expect(flow_net).to eq(3_000_000_000)
    end

    it '把资金账户清空后，原来那笔流水要冲销掉（否则账户余额虚增）' do
      sync!
      expect(flow_net).to eq(5_000_000_000)

      receipt.update!(cash_account_id: nil)
      sync!

      expect(flow_net).to eq(0)
    end
  end

  describe '自动凭证已过账后改单据' do
    let(:receipt) do
      account.erp_receipt_records.create!(
        crm_customer_id: customer.id, received_at: Time.zone.today, amount_micros: 8_000_000_000,
        currency: 'CNY', exchange_rate: 1, cash_account_id: cash_account.id, recorded_by_id: user.id
      )
    end

    it '不静默放过：凭证已记账就不能再改单据金额，得先红冲' do
      service = Erp::AutoVoucherService.new(account)
      voucher = service.for_receipt(receipt)
      Erp::VoucherPostingService.new(voucher, user).post!

      receipt.update!(amount_micros: 3_000_000_000)

      # 单据改了、凭证没改 → 总账与台账就此不平，且无人知晓
      expect { service.for_receipt(receipt.reload) }.to raise_error(Erp::AutoVoucherService::Error, /已记账/)
    end
  end
end
