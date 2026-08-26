# frozen_string_literal: true

require 'rails_helper'

# 「钱只能算一次」的守恒与幂等。
#
# 这些地方一旦松了，账面会**慢慢**偏——核销多算一笔、折旧重复提一个月、
# 坏账每点一次翻一倍，都不会报错，只会让报表越来越不对。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 金额守恒与幂等' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  describe '核销守恒（Erp::AllocationService）' do
    let(:ledger) do
      account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 100_000_000_000)
    end
    let(:receipt) do
      account.erp_receipt_records.create!(
        crm_customer_id: customer.id, received_at: Date.new(2026, 4, 10),
        amount_micros: 60_000_000_000, currency: 'CNY', exchange_rate: 1, recorded_by_id: user.id
      )
    end

    it '核销后台账已收金额与状态由核销重算' do
      Erp::AllocationService.new(receipt, :receipt).apply!([{ ledger_id: ledger.id, amount_micros: 60_000_000_000 }])

      expect(ledger.reload.received_amount_micros).to eq(60_000_000_000)
      expect(ledger.outstanding_micros).to eq(40_000_000_000)
      expect(ledger.status).to eq(Erp::Receivable::PARTIAL)
    end

    it '核销总额超过收款单金额时整单拒绝' do
      expect do
        Erp::AllocationService.new(receipt, :receipt).apply!([{ ledger_id: ledger.id, amount_micros: 70_000_000_000 }])
      end.to raise_error(Erp::AllocationService::Error)

      expect(ledger.reload.received_amount_micros).to eq(0)
    end

    it '单笔核销超过台账未结余额时拒绝' do
      big = account.erp_receipt_records.create!(
        crm_customer_id: customer.id, received_at: Date.new(2026, 4, 10),
        amount_micros: 200_000_000_000, currency: 'CNY', exchange_rate: 1, recorded_by_id: user.id
      )

      expect do
        Erp::AllocationService.new(big, :receipt).apply!([{ ledger_id: ledger.id, amount_micros: 150_000_000_000 }])
      end.to raise_error(Erp::AllocationService::Error)
    end

    it '重复 apply! 是整单覆盖，不累加' do
      service = Erp::AllocationService.new(receipt, :receipt)
      3.times { service.apply!([{ ledger_id: ledger.id, amount_micros: 60_000_000_000 }]) }

      expect(ledger.reload.received_amount_micros).to eq(60_000_000_000)
    end

    it '作废回滚全部核销与台账余额，单据留痕不删' do
      Erp::AllocationService.new(receipt, :receipt).apply!([{ ledger_id: ledger.id, amount_micros: 60_000_000_000 }])
      Erp::AllocationService.new(receipt, :receipt).void!

      expect(ledger.reload.received_amount_micros).to eq(0)
      expect(ledger.status).to eq(Erp::Receivable::UNPAID)
      expect(receipt.reload.status).to eq(Erp::ReceiptRecord::VOID)
      expect(account.erp_receipt_records.where(id: receipt.id)).to exist
    end
  end

  describe '期末事项幂等' do
    let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
    let(:usd_bank) { account.erp_ledger_accounts.find_by(code: '100202') }
    let(:income) { account.erp_ledger_accounts.find_by(code: '6001') }
    let(:usd_receivable) { account.erp_ledger_accounts.find_by(code: '112202') }

    def post!(lines, date:)
      voucher = account.erp_vouchers.create!(
        voucher_date: date, status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
        lines_attributes: lines.each_with_index.map { |line, index| line.merge(position: index) }
      )
      voucher.refresh_totals!
      Erp::VoucherPostingService.new(voucher, user).post!
    end

    it '同一汇率重复调汇不会重复生成凭证' do
      post!([
              { ledger_account_id: usd_receivable.id, direction: 'DEBIT', amount_micros: 1_000_000_000,
                currency: 'USD', exchange_rate: 7.0, crm_customer_id: customer.id },
              { ledger_account_id: income.id, direction: 'CREDIT', amount_micros: 7_000_000_000,
                currency: 'CNY', exchange_rate: 1 }
            ], date: Date.new(2026, 5, 10))

      service = Erp::RevaluationService.new(account, user)
      first = service.run!(period: '2026-05', rates: { 'USD' => '7.20' })
      expect(first[:voucher_no]).to be_present

      # 差额 = 1000 USD × (7.20 − 7.00) = 200 元
      voucher = account.erp_vouchers.find_by(voucher_no: first[:voucher_no])
      expect(voucher.total_debit_micros).to eq(200_000_000)
      Erp::VoucherPostingService.new(voucher, user).post!

      second = service.run!(period: '2026-05', rates: { 'USD' => '7.20' })
      expect(second[:voucher_no]).to be_nil
      expect(second[:count]).to eq(0)
    end

    it '调汇分录原币为 0、只动本位币' do
      post!([
              { ledger_account_id: usd_bank.id, direction: 'DEBIT', amount_micros: 1_000_000_000,
                currency: 'USD', exchange_rate: 7.0 },
              { ledger_account_id: income.id, direction: 'CREDIT', amount_micros: 7_000_000_000,
                currency: 'CNY', exchange_rate: 1 }
            ], date: Date.new(2026, 5, 10))

      result = Erp::RevaluationService.new(account, user).run!(period: '2026-05', rates: { 'USD' => '7.20' })
      line = account.erp_vouchers.find_by(voucher_no: result[:voucher_no])
                    .lines.find { |row| row.ledger_account_id == usd_bank.id }

      expect(line.amount_micros).to eq(0)
      expect(line.base_amount_micros).to eq(200_000_000)
    end

    it '坏账准备是余额科目，重复计提不翻倍' do
      account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 100_000_000_000)

      service = Erp::BadDebtService.new(account, user)
      first = service.run!(period: '2026-05', rates: { 'D30' => 10 })
      expect(first[:adjustment_micros]).to eq(10_000_000_000)

      Erp::VoucherPostingService.new(account.erp_vouchers.find_by(voucher_no: first[:voucher_no]), user).post!

      second = service.run!(period: '2026-05', rates: { 'D30' => 10 })
      expect(second[:booked_micros]).to eq(10_000_000_000)
      expect(second[:adjustment_micros]).to eq(0)
      expect(second[:voucher_no]).to be_nil
    end

    it '应计提数变小时生成转回分录' do
      account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 100_000_000_000)
      service = Erp::BadDebtService.new(account, user)

      first = service.run!(period: '2026-05', rates: { 'D30' => 10 })
      Erp::VoucherPostingService.new(account.erp_vouchers.find_by(voucher_no: first[:voucher_no]), user).post!

      second = service.run!(period: '2026-05', rates: { 'D30' => 4 })
      expect(second[:adjustment_micros]).to eq(-6_000_000_000)

      allowance = account.erp_ledger_accounts.find_by(code: '1231')
      line = account.erp_vouchers.find_by(voucher_no: second[:voucher_no])
                    .lines.find { |row| row.ledger_account_id == allowance.id }
      expect(line.direction).to eq(Erp::VoucherLine::DEBIT) # 转回＝借记坏账准备
    end
  end
end
