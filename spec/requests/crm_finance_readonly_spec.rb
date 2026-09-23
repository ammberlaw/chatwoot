require 'rails_helper'

# 财务（crm_finance 标记、无 crm_role）的 CRM 权限边界。
# 财务过不了 CRM 总门禁（can_access_crm? 要求 crm_role 非空），但对账必须看得到
# 销售订单与 PI，所以这两个控制器单独放行。边界一旦写错就是越权，用例钉死三件事：
# 看得见全员、写不了、其余 CRM 模块仍然进不去。
RSpec.describe 'CRM 财务只读', type: :request do
  let(:account) { create(:account) }
  let(:finance) { create(:user, account: account) }
  let(:salesperson) { create(:user, account: account) }
  let!(:own_order) { order_for(salesperson, 'SO-TEST-1') }
  let!(:other_order) { order_for(create(:user, account: account), 'SO-TEST-2') }

  # 没有销售订单的 factory，直接建。除了 name/order_no/order_date，
  # 模型还强制至少一个附件（PI/生产订单），所以挂一个占位文件。
  def order_for(owner, order_no)
    order = account.crm_sales_orders.new(name: "单-#{order_no}", order_no: order_no,
                                         order_date: Time.current, owner: owner)
    order.files.attach(io: StringIO.new('pi'), filename: "#{order_no}.pdf", content_type: 'application/pdf')
    order.save!
    order
  end

  before do
    finance.account_users.first.update!(crm_role: nil, crm_finance: true)
    salesperson.account_users.first.update!(crm_role: 'sales', crm_finance: false)
  end

  def auth(user) = { api_access_token: user.access_token.token }

  it '财务看得到全公司的销售订单（对账口径，不按业务员收敛）' do
    get "/api/v1/accounts/#{account.id}/crm/sales_orders", headers: auth(finance)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']['count']).to eq(2)
    expect(response.parsed_body['payload'].map { |o| o['order_no'] })
      .to contain_exactly(own_order.order_no, other_order.order_no)
  end

  it '财务不能新增或删除销售订单' do
    post "/api/v1/accounts/#{account.id}/crm/sales_orders",
         params: { sales_order: { name: 'x' } }, headers: auth(finance)
    expect(response).to have_http_status(:forbidden)

    delete "/api/v1/accounts/#{account.id}/crm/sales_orders/#{own_order.id}", headers: auth(finance)
    expect(response).to have_http_status(:forbidden)
  end

  it '财务进不了 CRM 的其余模块（客户资源不该给财务）' do
    get "/api/v1/accounts/#{account.id}/crm/customers", headers: auth(finance)

    expect(response).to have_http_status(:forbidden)
  end

  # 放行财务时改动了 visible_sales_orders，这里守住业务员的收敛没被顺带放宽。
  it '业务员仍然只看得到自己的订单' do
    get "/api/v1/accounts/#{account.id}/crm/sales_orders", headers: auth(salesperson)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']['count']).to eq(1)
  end
end
