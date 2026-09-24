require 'rails_helper'

# 明细关联产品档案 —— **建单不卡，转 ERP 时才卡**。
#
# 一开始做成了建单硬校验，后来发现行不通：有一部分定制品的编码是下单之后
# 工程/采购才给的，建单当场填不出来。而且 PI 付款自动生成订单那条路外层是
# `rescue StandardError` 只记日志，一卡就静默失败、订单凭空消失
#（近 90 天 211 张单里有 83 张、39% 走这条路）。
#
# 所以建单一律放行，把账算在 Crm::ErpOrderExport（转金蝶预检）那一步。
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

  it '明细没选产品也能建单（定制编码下单后才有）' do
    create_order([{ name: 'K717', quantity: 1, unit_price: 100 }])

    expect(response).to have_http_status(:success)
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
