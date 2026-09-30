require 'rails_helper'

# 销售订单 → 金蝶销售订单的转单预检。
#
# 建单时一律放行（定制编码下单后工程/采购才给），缺什么留到这一步算账：
# 客户 ERP 编码 / 收款方式 / 明细关联产品 / 数量。运费行不要求关联产品。
RSpec.describe '销售订单转 ERP 预检', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:product) { account.crm_products.create!(name: '43寸吊挂广告机', sku: 'P.TEST.001', unit: 'PCS') }
  let(:customer) { account.crm_customers.create!(name: 'ACME', customer_code: 'C.0001') }

  before { user.account_users.first.update!(crm_role: 'sales') }

  def auth = { api_access_token: user.access_token.token }

  # 订单模型要求新建时至少一个附件（PI/生产订单），这里挂一张占位图。
  def build_order(items, **attrs)
    order = account.crm_sales_orders.new(
      { name: '测试单', order_no: "SO-E#{SecureRandom.hex(3)}", order_date: Time.current,
        owner_id: user.id, crm_customer_id: customer.id, payment_term: 'TT30',
        order_kind: 'CUSTOM', line_items: items }.merge(attrs)
    )
    order.files.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'pi.png',
                       content_type: 'image/png')
    order.save!
    order
  end

  def preflight(order)
    get "/api/v1/accounts/#{account.id}/crm/sales_orders/#{order.id}/erp_export", headers: auth
    response.parsed_body['payload']
  end

  it '该有的都有时判定可转，并带出物料编码与单位' do
    order = build_order([{ 'name' => 'Q75x', 'quantity' => 2, 'unit_price' => 100,
                           'crm_product_id' => product.id }])

    body = preflight(order)
    expect(body['ready']).to be(true)
    expect(body['blockers']).to be_empty
    expect(body['lines'].first).to include('product_sku' => 'P.TEST.001', 'product_unit' => 'PCS')
    expect(body['header']).to include('customer_code' => 'C.0001', 'payment_term' => 'TT30')
  end

  it '明细没关联产品时指出是第几行' do
    order = build_order([{ 'name' => '已关联', 'quantity' => 1, 'crm_product_id' => product.id },
                         { 'name' => 'K717', 'quantity' => 1 }])

    body = preflight(order)
    expect(body['ready']).to be(false)
    blocker = body['blockers'].find { |b| b['type'] == 'line_product' }
    expect(blocker['rows']).to eq([2])
  end

  it '运费行不要求关联产品' do
    order = build_order([{ 'name' => 'Freight', 'quantity' => 1, 'unit_price' => 50 }])

    body = preflight(order)
    expect(body['lines'].first['fee']).to be(true)
    expect(body['blockers'].map { |b| b['type'] }).not_to include('line_product')
  end

  it '客户没有 ERP 编码、收款方式没填时都拦下来' do
    customer.update!(customer_code: nil)
    order = build_order([{ 'name' => 'Q75x', 'quantity' => 1, 'crm_product_id' => product.id }],
                        payment_term: nil)

    types = preflight(order)['blockers'].map { |b| b['type'] }
    expect(types).to include('customer_code', 'payment_term')
  end

  it '数量为零的行拦下来' do
    order = build_order([{ 'name' => 'Q75x', 'quantity' => 0, 'crm_product_id' => product.id }])

    blocker = preflight(order)['blockers'].find { |b| b['type'] == 'line_quantity' }
    expect(blocker['rows']).to eq([1])
  end
end
