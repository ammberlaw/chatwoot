# frozen_string_literal: true

require 'rails_helper'

# 边界与守卫：重复操作、已停用/分类科目、删除保护。
# 这些都是「用户手快点两下」或「点错科目」就会碰上的，出错必须当场拦住而不是记进账。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'ERP 边界守卫' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:cash) { account.erp_ledger_accounts.find_by(code: '1001') }
  let(:asset_group) { account.erp_ledger_accounts.find_by(code: '1') }

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  def build_voucher(debit_account, credit_account)
    account.erp_vouchers.new(
      voucher_date: Time.zone.today, status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
      lines_attributes: [
        { ledger_account_id: debit_account.id, direction: 'DEBIT', amount_micros: 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 0 },
        { ledger_account_id: credit_account.id, direction: 'CREDIT', amount_micros: 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 1 }
      ]
    )
  end

  describe '科目守卫' do
    it '分类科目不能直接记账' do
      voucher = build_voucher(asset_group, bank)

      expect(voucher).not_to be_valid
      expect(voucher.errors.full_messages.join).to include('末级')
    end

    it '已停用的科目不能记账' do
      cash.update!(is_active: false)
      voucher = build_voucher(cash, bank)

      expect(voucher).not_to be_valid
      expect(voucher.errors.full_messages.join).to include('停用')
    end

    it '有下级的科目删不掉' do
      parent = account.erp_ledger_accounts.find_by(code: '1002')

      expect(parent.destroy).to be(false)
      expect(parent.errors.full_messages.join).to be_present
    end

    it '已有分录的科目删不掉' do
      voucher = build_voucher(cash, bank)
      voucher.save!
      voucher.refresh_totals!
      Erp::VoucherPostingService.new(voucher, user).post!

      expect(cash.reload.destroy).to be(false)
    end
  end

  describe '凭证状态机' do
    let(:voucher) do
      record = build_voucher(cash, bank)
      record.save!
      record.refresh_totals!
      record
    end

    it '同一张凭证不能过账两次' do
      Erp::VoucherPostingService.new(voucher, user).post!

      expect { Erp::VoucherPostingService.new(voucher.reload, user).post! }
        .to raise_error(Erp::VoucherPostingService::Error, /不是待过账/)
    end

    it '同一张凭证不能红冲两次' do
      Erp::VoucherPostingService.new(voucher, user).post!
      Erp::VoucherPostingService.new(voucher.reload, user).reverse!

      expect { Erp::VoucherPostingService.new(voucher.reload, user).reverse! }
        .to raise_error(Erp::VoucherPostingService::Error, /红冲过/)
    end

    it '待过账凭证不能红冲（还没进账，直接作废即可）' do
      expect { Erp::VoucherPostingService.new(voucher, user).reverse! }
        .to raise_error(Erp::VoucherPostingService::Error, /已记账/)
    end

    it '单边凭证过不了账' do
      single = account.erp_vouchers.create!(
        voucher_date: Time.zone.today, status: Erp::Voucher::DRAFT,
        lines_attributes: [
          { ledger_account_id: cash.id, direction: 'DEBIT', amount_micros: 1_000_000,
            currency: 'CNY', exchange_rate: 1, position: 0 }
        ]
      )
      single.refresh_totals!

      expect { Erp::VoucherPostingService.new(single, user).post! }
        .to raise_error(Erp::VoucherPostingService::Error)
    end
  end

  describe '固定资产' do
    let(:asset) do
      account.erp_fixed_assets.create!(
        name: '打样机', asset_no: 'FA-001', original_value_micros: 120_000_000_000,
        residual_rate: 5, useful_months: 60, purchased_at: Date.new(2026, 1, 10),
        status: Erp::FixedAsset::IN_USE
      )
    end

    it '同一期间重复计提不会翻倍' do
      asset # let 是惰性的，先把资产建出来再计提
      service = Erp::DepreciationService.new(account, user)
      first = service.run!('2026-03')
      second = service.run!('2026-03')

      expect(first[:count]).to eq(1)
      expect(second[:count]).to eq(0)
      expect(asset.reload.accumulated_depreciation_micros).to eq(first[:amount_micros])
    end

    it '已处置的资产不能再处置' do
      service = Erp::DepreciationService.new(account, user)
      service.dispose!(asset, disposed_at: Date.new(2026, 4, 1), income_micros: 0)

      expect { service.dispose!(asset.reload, disposed_at: Date.new(2026, 5, 1), income_micros: 0) }
        .to raise_error(Erp::DepreciationService::Error, /已处置/)
    end

    it '处置后不再计提折旧' do
      service = Erp::DepreciationService.new(account, user)
      service.dispose!(asset, disposed_at: Date.new(2026, 4, 1), income_micros: 0)

      expect(service.run!('2026-05')[:count]).to eq(0)
    end
  end
end
