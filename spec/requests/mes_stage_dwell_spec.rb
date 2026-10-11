# frozen_string_literal: true

require 'rails_helper'

# 生产看板的「阶段停留」。
#
# 阶段分布只给头数：25 张单在采购本身不吓人，「25 张平均卡了 12.7 天、最久 45 天」
# 才是要盯的那个数。这个时间维度原来看板上没有，于是整条线唯一的瓶颈在界面上看不见。
RSpec.describe 'MES 生产看板 · 阶段停留', type: :request do
  let(:account) { create(:account) }
  let(:pmc) { create(:user, account: account) }

  before { pmc.account_users.first.update!(role: :administrator, mes_roles: ['pmc']) }

  # is_draft 由审批状态派生（仅 APPROVED 才是正式单，看板只看正式单），所以要走审批通过这条路。
  # 建单时模型会自动落一条当前阶段的事件（每单每阶段唯一），这里只把进入时间拨回去。
  def order_at(stage, entered_days_ago, line: 'TABLET')
    order = account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品', qty: 1,
      stage: stage, owner_id: pmc.id, product_line: line, approval_status: 'APPROVED'
    )
    order.stage_events.find_by!(stage: stage).update!(entered_at: entered_days_ago.days.ago)
    order
  end

  def dwell
    get "/api/v1/accounts/#{account.id}/mes/dashboard",
        headers: { api_access_token: pmc.access_token.token }
    response.parsed_body['stage_dwell']
  end

  it '按阶段给出在产单数、平均停留天数与最久天数' do
    order_at('PURCHASING', 10)
    order_at('PURCHASING', 20)
    order_at('PRODUCTION', 2)

    result = dwell

    expect(result['PURCHASING']).to include('count' => 2, 'avg_days' => 15.0, 'max_days' => 20.0)
    expect(result['PRODUCTION']).to include('count' => 1, 'avg_days' => 2.0)
  end

  it '已出货的单不算（已经走完了，不叫卡住）' do
    order_at('SHIPPED', 30)
    order_at('PURCHASING', 5)

    result = dwell

    expect(result).not_to have_key('SHIPPED')
    expect(result['PURCHASING']['count']).to eq(1)
  end

  it '退回重进后按本次进入算，不把上一轮的时长累上去' do
    order = order_at('PURCHASING', 40)
    order.stage_events.find_by!(stage: 'PURCHASING').update!(entered_at: 3.days.ago)

    expect(dwell['PURCHASING']['avg_days']).to eq(3.0)
  end

  it '没有阶段事件的老单跳过——算不出来就不算，不拿创建时间凑数' do
    order = order_at('PURCHASING', 9)
    order.stage_events.destroy_all

    expect(dwell).to be_empty
  end

  it '草稿单（未审批通过）与已取消的单不计入' do
    order_at('PURCHASING', 9).update!(approval_status: 'DRAFT')
    order_at('PURCHASING', 9).update!(status: 'CANCELLED')

    expect(dwell).to be_empty
  end

  it '跟着产品线筛选走（切到某条线只看该线的）' do
    order_at('PURCHASING', 6)
    order_at('PURCHASING', 30, line: 'COMMERCIAL_DISPLAY')

    get "/api/v1/accounts/#{account.id}/mes/dashboard",
        params: { product_line: 'TABLET' }, headers: { api_access_token: pmc.access_token.token }

    expect(response.parsed_body['stage_dwell']['PURCHASING']).to include('count' => 1, 'avg_days' => 6.0)
  end
end
