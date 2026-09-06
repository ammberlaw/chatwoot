# frozen_string_literal: true

require 'rails_helper'

# 期间控制：结账顺序与反结账的连锁影响。
#
# 这一块错了不会当场报错，但会让「已结账」这三个字失去意义——
# 结转凭证是层层叠上去的，跳着结、乱着反结，账面就悄悄错位了。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 期间控制' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:income) { account.erp_ledger_accounts.find_by(code: '6001') }
  let(:office) { account.erp_ledger_accounts.find_by(code: '660202') }
  let(:service) { Erp::PeriodCloseService.new(account, user) }

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

  describe '结账顺序' do
    before do
      post!(Date.new(2026, 3, 10), bank, income, 50_000)
      post!(Date.new(2026, 4, 10), office, bank, 8_000)
    end

    it '前面的期间还开着时，不让先结后面的' do
      expect { service.close!('2026-04') }
        .to raise_error(Erp::PeriodCloseService::Error, /2026-03/)
    end

    it '按顺序结就没问题' do
      expect { service.close!('2026-03') }.not_to raise_error
      expect { service.close!('2026-04') }.not_to raise_error
    end
  end

  describe '反结账' do
    before do
      post!(Date.new(2026, 3, 10), bank, income, 50_000)
      post!(Date.new(2026, 4, 10), office, bank, 8_000)
      service.close!('2026-03')
      service.close!('2026-04')
    end

    it '后面的期间还锁着时，不让反结前面的（结转凭证是层层叠的）' do
      expect { service.reopen!('2026-03') }
        .to raise_error(Erp::PeriodCloseService::Error, /2026-04/)
    end

    it '从最后一个期间倒着反结就没问题' do
      expect { service.reopen!('2026-04') }.not_to raise_error
      expect { service.reopen!('2026-03') }.not_to raise_error
    end
  end
end
