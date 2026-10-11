# frozen_string_literal: true

require 'rails_helper'

# 开账体检。
#
# 功能齐了不等于账开了：没建会计期间、没录期初、订单没建应收台账、凭证一张没过账时，
# 系统照样天天正确地生成凭证，而科目余额和报表永远是空的——界面上看起来像「ERP 没跑起来」。
# 这个服务就是把那几个人工动作的欠账数出来，摆到财务看板上。
RSpec.describe Erp::OpeningReadiness do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }

  def sales_order(status: 'IN_PRODUCTION', date: Time.zone.today)
    order = account.crm_sales_orders.new(
      name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: date,
      status: status, order_kind: 'CUSTOM', crm_customer_id: customer.id, owner_id: user.id,
      order_amount_micros: 100_000_000, order_currency: 'CNY', exchange_rate: 1
    )
    order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!
    order
  end

  it '什么都没做时四项全欠：期间 0、期初未录、订单待建账、零张过账' do
    sales_order

    result = described_class.new(account).call

    expect(result[:fiscal_period_count]).to eq(0)
    expect(result[:opening_balance_ready]).to be(false)
    expect(result[:pending_receivable_count]).to eq(1)
    expect(result[:posted_voucher_count]).to eq(0)
  end

  it '待确认与已取消的订单不算待建账（本来就不该进应收）' do
    sales_order(status: 'PENDING_CONFIRMATION')
    sales_order(status: 'CANCELLED')
    sales_order(status: 'SHIPPED')

    expect(described_class.new(account).call[:pending_receivable_count]).to eq(1)
  end

  it '已建台账的订单不再算欠账' do
    order = sales_order
    account.erp_receivables.create!(crm_customer_id: customer.id, crm_sales_order_id: order.id,
                                    total_amount_micros: 100_000_000, currency: 'CNY', exchange_rate: 1)

    expect(described_class.new(account).call[:pending_receivable_count]).to eq(0)
  end

  it '会计启用日之前的历史单不算待建账（否则清单里全是钱早收完的假应收）' do
    Erp::Setting.for_account(account).update!(fiscal_start_date: Date.new(2026, 10, 1))
    sales_order(date: Date.new(2026, 8, 20))
    sales_order(date: Date.new(2026, 10, 9))

    expect(described_class.new(account).call[:pending_receivable_count]).to eq(1)
  end

  it '录过期初余额后那一项打勾' do
    Erp::ChartOfAccountsService.ensure_standard!(account)
    bank = account.erp_ledger_accounts.find_by(code: '100201')
    capital = account.erp_ledger_accounts.find_by(code: '4001')
    Erp::OpeningBalanceService.new(account, user).save!(
      rows: [{ ledger_account_id: bank.id, debit_micros: 500_000_000 },
             { ledger_account_id: capital.id, credit_micros: 500_000_000 }],
      as_of: Date.new(2026, 10, 1)
    )

    expect(described_class.new(account).call[:opening_balance_ready]).to be(true)
  end

  it '待过账与已过账分开数（报表空不空看的是已过账那个数）' do
    Erp::ChartOfAccountsService.ensure_standard!(account)
    bank = account.erp_ledger_accounts.find_by(code: '100201')
    capital = account.erp_ledger_accounts.find_by(code: '4001')
    voucher = account.erp_vouchers.create!(
      voucher_date: Time.zone.today, summary: '股东投入', status: Erp::Voucher::DRAFT, prepared_by_id: user.id,
      lines_attributes: [
        { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: 100_000_000,
          currency: 'CNY', exchange_rate: 1, position: 0 },
        { ledger_account_id: capital.id, direction: 'CREDIT', amount_micros: 100_000_000,
          currency: 'CNY', exchange_rate: 1, position: 1 }
      ]
    )
    voucher.refresh_totals!

    expect(described_class.new(account).call).to include(draft_voucher_count: 1, posted_voucher_count: 0)

    Erp::VoucherPostingService.new(voucher, user).post!

    expect(described_class.new(account).call).to include(draft_voucher_count: 0, posted_voucher_count: 1)
  end

  it '应收台账页的「待建账」清单与看板用同一个 scope（两处数字必须一致）' do
    Erp::Setting.for_account(account).update!(fiscal_start_date: Date.new(2026, 10, 1))
    sales_order(date: Date.new(2026, 8, 20))
    sales_order(date: Date.new(2026, 10, 9))

    readiness = described_class.new(account)
    expect(readiness.pending_order_scope.count).to eq(1)
    expect(readiness.unfiltered_pending_scope.count).to eq(2)
  end
end
