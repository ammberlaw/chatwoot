# frozen_string_literal: true

require 'rails_helper'

# 销售订单一键转生产订单：一张多型号的销售订单要能一次转出多张生产订单。
#
# 原来这里只转第一行明细（前端 rows[0] + 后端整单幂等），剩下的品项业务员得去 MES
# 手工另开单，还挂不回同一张销售订单——追溯、成本归集、毛利就都少一截。
# 生产上 8 月起的单里有 37 张是多行明细，正卡在这儿。
RSpec.describe 'MES 销售订单转生产订单', type: :request do
  let(:account) { create(:account) }
  let(:pmc) { create(:user, account: account) }
  let(:sales) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }
  let(:board) { account.crm_products.create!(name: '10.4寸工业屏', sku: 'P.A') }
  let(:kiosk) { account.crm_products.create!(name: '43寸广告机', sku: 'P.B') }

  before do
    pmc.account_users.first.update!(role: :agent, mes_roles: ['pmc'])
    sales.account_users.first.update!(role: :agent, crm_role: 'sales', mes_roles: [])
  end

  def auth(user)
    { api_access_token: user.access_token.token }
  end

  def sales_order(items)
    order = account.crm_sales_orders.new(
      name: '多型号订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
      order_kind: 'CUSTOM', status: 'PENDING_CONFIRMATION',
      crm_customer_id: customer.id, owner_id: sales.id, line_items: items
    )
    order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!
    order
  end

  def convert(order, items, as:)
    post "/api/v1/accounts/#{account.id}/mes/production_orders/convert",
         params: { crm_sales_order_id: order.id, items: items }, headers: auth(as)
  end

  def two_line_order
    sales_order([{ 'name' => '10.4寸工业屏', 'quantity' => 20 },
                 { 'name' => '43寸广告机', 'quantity' => 5 }])
  end

  def two_rows
    [{ crm_product_id: board.id, qty: 20, unit: '台' },
     { crm_product_id: kiosk.id, qty: 5, unit: '台' }]
  end

  it '两行明细一次转出两张生产订单，都挂回同一张销售订单' do
    order = two_line_order
    convert(order, two_rows, as: pmc)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['order_nos'].size).to eq(2)

    made = account.mes_production_orders.where(crm_sales_order_id: order.id)
    expect(made.count).to eq(2)
    expect(made.pluck(:crm_product_id)).to contain_exactly(board.id, kiosk.id)
    expect(made.pluck(:qty).map(&:to_i)).to contain_exactly(20, 5)
  end

  it '转完销售订单进入生产中' do
    order = two_line_order
    convert(order, two_rows, as: pmc)

    expect(order.reload.status).to eq('IN_PRODUCTION')
  end

  it '重复转同样的行不会再建（连点两下/重试都撞得上）' do
    order = two_line_order
    convert(order, two_rows, as: pmc)
    convert(order, two_rows, as: pmc)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.mes_production_orders.where(crm_sales_order_id: order.id).count).to eq(2)
  end

  it '订单后来补了一行，再转只补那一行' do
    order = two_line_order
    convert(order, [two_rows.first], as: pmc)
    convert(order, two_rows, as: pmc)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['order_nos'].size).to eq(1)
    expect(response.parsed_body['skipped']).to eq(1)
    expect(account.mes_production_orders.where(crm_sales_order_id: order.id).count).to eq(2)
  end

  it '已取消的生产订单不占位，可以重新转' do
    order = two_line_order
    convert(order, [two_rows.first], as: pmc)
    account.mes_production_orders.find_by(crm_product_id: board.id).update!(status: 'CANCELLED')
    convert(order, [two_rows.first], as: pmc)

    expect(response).to have_http_status(:success)
    expect(account.mes_production_orders.where(crm_sales_order_id: order.id, status: 'IN_PROGRESS').count).to eq(1)
  end

  it '业务员转的每一张都落草稿进审批，不能绕过审批链' do
    order = two_line_order
    convert(order, two_rows, as: sales)

    expect(response).to have_http_status(:success)
    made = account.mes_production_orders.where(crm_sales_order_id: order.id)
    expect(made.count).to eq(2)
    # 停在哪一环取决于账套配没配部门主管（没配就直接到总经理），
    # 这里要守的是「没生效、下游看不见」，不是具体停在哪个环节。
    expect(made.pluck(:approval_status)).to all(satisfy { |st| st != 'APPROVED' })
    expect(made.pluck(:is_draft).uniq).to eq([true])
  end

  it 'PMC 转的直接生效，下游立刻看得见' do
    order = two_line_order
    convert(order, two_rows, as: pmc)

    made = account.mes_production_orders.where(crm_sales_order_id: order.id)
    expect(made.pluck(:approval_status).uniq).to eq(['APPROVED'])
    expect(made.pluck(:is_draft).uniq).to eq([false])
  end

  it '没选产品或数量为零的行直接忽略，不会建出空单' do
    order = two_line_order
    convert(order, [{ crm_product_id: board.id, qty: 0 }, { crm_product_id: '', qty: 3 }], as: pmc)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.mes_production_orders.where(crm_sales_order_id: order.id).count).to eq(0)
  end

  it '一行建单失败则整批回滚，不留半截' do
    order = two_line_order
    allow_any_instance_of(Mes::ProductionOrder).to receive(:save!).and_wrap_original do |m, *args| # rubocop:disable RSpec/AnyInstance
      raise ActiveRecord::RecordInvalid if m.receiver.crm_product_id == kiosk.id

      m.call(*args)
    end
    convert(order, two_rows, as: pmc)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.mes_production_orders.where(crm_sales_order_id: order.id).count).to eq(0)
  end

  it '转单预览会标出哪几行已经转过' do
    order = two_line_order
    convert(order, [two_rows.first], as: pmc)

    get "/api/v1/accounts/#{account.id}/crm/sales_orders/#{order.id}/convert_preview", headers: auth(sales)

    rows = response.parsed_body['payload']
    expect(rows.find { |r| r['crm_product_id'] == board.id }['converted_order_no']).to be_present
    expect(rows.find { |r| r['crm_product_id'] == kiosk.id }['converted_order_no']).to be_nil
  end
end
