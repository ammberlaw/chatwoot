# frozen_string_literal: true

require 'rails_helper'

# 批量过账。自动凭证天天在产，一张一张点是「凭证天天生成、报表永远是空的」最后那道人力卡口。
# 批量过账必须做到：平的过掉、不平的单独报出来不拖垮整批、不是待过账的既不算成功也不算失败。
RSpec.describe 'ERP 凭证批量过账', type: :request do
  let(:account) { create(:account) }
  let(:finance) { create(:user, account: account) }
  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:capital) { account.erp_ledger_accounts.find_by(code: '4001') }

  before do
    Erp::ChartOfAccountsService.ensure_standard!(account)
    finance.account_users.first.update!(role: :administrator)
  end

  def draft(summary, debit_yuan, credit_yuan)
    voucher = account.erp_vouchers.create!(
      voucher_date: Time.zone.today, summary: summary, status: Erp::Voucher::DRAFT,
      prepared_by_id: finance.id,
      lines_attributes: [
        { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: debit_yuan * 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 0 },
        { ledger_account_id: capital.id, direction: 'CREDIT', amount_micros: credit_yuan * 1_000_000,
          currency: 'CNY', exchange_rate: 1, position: 1 }
      ]
    )
    voucher.refresh_totals!
    voucher
  end

  def bulk_post(ids)
    post "/api/v1/accounts/#{account.id}/erp/vouchers/bulk_post",
         params: { voucher_ids: ids }, headers: { api_access_token: finance.access_token.token }
  end

  it '把选中的待过账凭证一次全过掉' do
    vouchers = [draft('A', 100, 100), draft('B', 200, 200), draft('C', 300, 300)]

    bulk_post(vouchers.map(&:id))

    expect(response).to have_http_status(:success)
    payload = response.parsed_body['payload']
    expect(payload['posted']).to eq(3)
    expect(payload['failed']).to be_empty
    expect(account.erp_vouchers.where(status: Erp::Voucher::POSTED).count).to eq(3)
  end

  it '借贷不平的那张单独报出来，其余照常过账' do
    good = draft('平的', 100, 100)
    bad = draft('不平的', 100, 90)

    bulk_post([good.id, bad.id])

    payload = response.parsed_body['payload']
    expect(payload['posted']).to eq(1)
    expect(payload['failed'].first['voucher_no']).to eq(bad.voucher_no)
    expect(payload['failed'].first['error']).to include('借贷不平')
    expect(good.reload.status).to eq(Erp::Voucher::POSTED)
    expect(bad.reload.status).to eq(Erp::Voucher::DRAFT)
  end

  it '已过账的混在选中项里只算 skipped，不重复过账也不报错' do
    already = draft('已过账', 100, 100)
    Erp::VoucherPostingService.new(already, finance).post!
    pending_voucher = draft('待过账', 50, 50)

    bulk_post([already.id, pending_voucher.id])

    payload = response.parsed_body['payload']
    expect(payload['posted']).to eq(1)
    expect(payload['skipped']).to eq(1)
    expect(payload['failed']).to be_empty
  end

  it '期间已结账的凭证报出「已结账」原因，而不是静默跳过' do
    voucher = draft('冻结期', 100, 100)
    account.erp_fiscal_periods.create!(period: voucher.period, status: Erp::FiscalPeriod::CLOSED)

    bulk_post([voucher.id])

    payload = response.parsed_body['payload']
    expect(payload['posted']).to eq(0)
    expect(payload['failed'].first['error']).to include('已结账')
  end

  it '一个都没选时明确拒绝' do
    bulk_post([])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('请先选择')
  end

  it '超过单次上限时拒绝并提示分批（防撞 15 秒请求时限）' do
    bulk_post((1..(Api::V1::Accounts::Erp::VouchersController::BULK_POST_LIMIT + 1)).to_a)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('分批')
  end
end
