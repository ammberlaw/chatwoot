# frozen_string_literal: true

require 'rails_helper'

# 驼峰 perPage 的静默截断。
#
# 后端读 params[:per_page]（下划线）。前端写成驼峰 perPage 时读不到，于是**静默回落到
# 默认每页条数**——界面上就是「数据少了一截」，不报错、查不出来（商机列表和商机看板
# 都栽过，两处至今靠源码注释提醒下一个人别写驼峰）。注释防不住，在基类统一折回。
RSpec.describe '分页参数驼峰容错', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account) }

  before { admin.account_users.first.update!(role: :administrator) }

  def auth
    { api_access_token: admin.access_token.token }
  end

  context 'with CRM 销售订单（默认每页 15 条）' do
    before do
      customer = create(:crm_customer, account: account)
      20.times do |i|
        order = account.crm_sales_orders.new(
          name: "订单#{i}", order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
          status: 'IN_PRODUCTION', order_kind: 'CUSTOM', crm_customer_id: customer.id, owner_id: admin.id,
          order_amount_micros: 1_000_000, order_currency: 'CNY', exchange_rate: 1
        )
        order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
        order.save!
      end
    end

    it '不传每页条数时回落到 15 条' do
      get "/api/v1/accounts/#{account.id}/crm/sales_orders", headers: auth

      expect(response.parsed_body['payload'].size).to eq(15)
    end

    it '下划线 per_page 照常生效' do
      get "/api/v1/accounts/#{account.id}/crm/sales_orders", params: { per_page: 20 }, headers: auth

      expect(response.parsed_body['payload'].size).to eq(20)
    end

    it '驼峰 perPage 现在也认（原来会悄悄只返回 15 条）' do
      get "/api/v1/accounts/#{account.id}/crm/sales_orders", params: { perPage: 20 }, headers: auth

      expect(response.parsed_body['payload'].size).to eq(20)
    end

    it '两个都传时以下划线为准（显式写法优先，不互相覆盖）' do
      get "/api/v1/accounts/#{account.id}/crm/sales_orders",
          params: { per_page: 3, perPage: 20 }, headers: auth

      expect(response.parsed_body['payload'].size).to eq(3)
    end
  end

  context 'with ERP 凭证' do
    before do
      Erp::ChartOfAccountsService.ensure_standard!(account)
      bank = account.erp_ledger_accounts.find_by(code: '100201')
      capital = account.erp_ledger_accounts.find_by(code: '4001')
      18.times do
        account.erp_vouchers.create!(
          voucher_date: Time.zone.today, summary: '测试', status: Erp::Voucher::DRAFT, prepared_by_id: admin.id,
          lines_attributes: [
            { ledger_account_id: bank.id, direction: 'DEBIT', amount_micros: 1_000_000,
              currency: 'CNY', exchange_rate: 1, position: 0 },
            { ledger_account_id: capital.id, direction: 'CREDIT', amount_micros: 1_000_000,
              currency: 'CNY', exchange_rate: 1, position: 1 }
          ]
        )
      end
    end

    it '驼峰 perPage 也认' do
      get "/api/v1/accounts/#{account.id}/erp/vouchers", params: { perPage: 18 }, headers: auth

      expect(response.parsed_body['payload'].size).to eq(18)
    end
  end

  context 'with MES 生产订单' do
    before do
      18.times do
        account.mes_production_orders.create!(
          order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品', qty: 1,
          stage: 'PRODUCTION', owner_id: admin.id, product_line: 'TABLET'
        )
      end
    end

    it '驼峰 perPage 也认' do
      get "/api/v1/accounts/#{account.id}/mes/production_orders", params: { perPage: 18 }, headers: auth

      expect(response.parsed_body['payload'].size).to eq(18)
    end
  end
end
