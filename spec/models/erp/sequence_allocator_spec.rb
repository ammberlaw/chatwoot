# frozen_string_literal: true

require 'rails_helper'

# 单据取号：并发撞号与序号溢出这两个 bug 的回归测试。
#
# 并发那半边在 RSpec 里测不了（事务隔离让别的连接看不见测试数据），
# 已用 8 线程实跑验证过；这里锁住可测的部分：序号按数值取最大、取号时确实上了 advisory lock。
RSpec.describe Erp::SequenceAllocator do
  let(:account) { create(:account) }
  let(:customer) { create(:crm_customer, account: account) }
  let(:today) { Time.zone.today.strftime('%Y%m%d') }

  describe '序号按数值取最大' do
    it '第 99 张之后接 100、101，不会卡在 99 反复撞号' do
      account.erp_receivables.create!(
        receivable_no: "AR-#{today}-99", crm_customer_id: customer.id, total_amount_micros: 1_000_000
      )

      first = account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 1_000_000)
      second = account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 1_000_000)

      expect(first.receivable_no).to eq("AR-#{today}-100")
      expect(second.receivable_no).to eq("AR-#{today}-101")
    end

    it '空号段从 01 开始' do
      record = account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 1_000_000)

      expect(record.receivable_no).to eq("AR-#{today}-01")
    end

    it '凭证号按月连号，跨月各自从 0001 起' do
      Erp::ChartOfAccountsService.ensure_standard!(account)
      bank = account.erp_ledger_accounts.find_by(code: '100201')
      cash = account.erp_ledger_accounts.find_by(code: '1001')

      make = lambda { |date|
        account.erp_vouchers.create!(
          voucher_date: date, status: Erp::Voucher::DRAFT,
          lines_attributes: [
            { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: 1_000_000, currency: 'CNY', exchange_rate: 1 },
            { ledger_account_id: cash.id, direction: 'CREDIT', amount_micros: 1_000_000, currency: 'CNY', exchange_rate: 1 }
          ]
        ).voucher_no
      }

      expect(make.call(Date.new(2026, 6, 3))).to eq('记-2026-06-0001')
      expect(make.call(Date.new(2026, 6, 8))).to eq('记-2026-06-0002')
      expect(make.call(Date.new(2026, 7, 1))).to eq('记-2026-07-0001')
    end
  end

  describe '并发保护' do
    it '取号时按 (账户, 号段前缀) 上事务级 advisory lock' do
      allow(described_class).to receive(:lock!).and_call_original

      account.erp_receivables.create!(crm_customer_id: customer.id, total_amount_micros: 1_000_000)

      expect(described_class).to have_received(:lock!).with(account, "AR-#{today}-")
    end
  end
end
