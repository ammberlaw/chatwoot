require 'rails_helper'

# 明细必须关联产品档案 —— 只卡「手工建单」这一条路。
#
# 为什么不做成模型校验：PI 付款会自动生成销售订单，而那条调用外层是
# `rescue StandardError` 只记日志。模型层一拦，订单会静默不生成、没人收到报错。
# 近 90 天 211 张单里有 83 张（39%）就是这么来的，砸掉就是生产事故。
RSpec.describe '销售订单明细关联产品', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:product) { account.crm_products.create!(name: '43寸吊挂广告机', sku: 'P.TEST.001') }

  before { user.account_users.first.update!(crm_role: 'sales') }

  def auth = { api_access_token: user.access_token.token }

  def create_order(items)
    post "/api/v1/accounts/#{account.id}/crm/sales_orders",
         params: {
           sales_order: {
             name: '测试单', order_no: "SO-T#{SecureRandom.hex(3)}", order_date: Time.current.iso8601,
             line_items_json: items.to_json,
             files: [fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')]
           }
         }, headers: auth
  end

  it '明细没选产品时建不了单，并指出是第几行' do
    create_order([{ name: 'K717', quantity: 1, unit_price: 100 }])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include('第 1 行')
  end

  it '选了产品就能建，并记住「这段叫法 → 这个产品」' do
    create_order([{ name: 'Q75x', quantity: 1, unit_price: 100, crm_product_id: product.id }])

    expect(response).to have_http_status(:success)
    alias_row = Crm::ProductAlias.find_by(account_id: account.id, normalized_text: 'q75x')
    expect(alias_row&.crm_product_id).to eq(product.id)
  end

  # 这条是防线：PI 自动生成订单那条路不能被新校验拦住。
  it 'PI 付款自动生成订单不受影响（明细没产品也照样生成）' do
    order = account.crm_sales_orders.new(
      name: 'PI 自动单', order_no: "SO-A#{SecureRandom.hex(3)}", order_date: Time.current,
      line_items: [{ 'name' => 'Android board', 'quantity' => 1 }], owner: user
    )
    order.files.attach(io: StringIO.new('pi'), filename: 'pi.pdf', content_type: 'application/pdf')

    expect(order.save).to be(true)
    expect(order.reload.line_items.first['crm_product_id']).to be_nil
  end

  # 「只卡新建」：编辑旧单不该被迫先补齐历史明细。
  it '编辑已有订单不要求补产品' do
    order = account.crm_sales_orders.new(
      name: '旧单', order_no: "SO-O#{SecureRandom.hex(3)}", order_date: Time.current,
      line_items: [{ 'name' => '老明细', 'quantity' => 1 }], owner: user
    )
    order.files.attach(io: StringIO.new('pi'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!

    patch "/api/v1/accounts/#{account.id}/crm/sales_orders/#{order.id}",
          params: { sales_order: { delivery_date: 3.days.from_now.iso8601 } }, headers: auth

    expect(response).to have_http_status(:success)
  end
end
