# frozen_string_literal: true

require 'rails_helper'

# 产线为空被隐藏，要能看见。
#
# 产线分流是 where(product_line = 当前产线)，没设产线的单据在任何一条具体产线下都查不到，
# 页面上和「数据丢了」长得一模一样（BOM 丢过 3 条、BOM 模版丢过 2 条，每次都要人来查）。
# 列表 meta 带回被筛掉的条数，前端才有东西可提示。
RSpec.describe 'MES 产线为空被隐藏的提示', type: :request do
  let(:account) { create(:account) }
  let(:pmc) { create(:user, account: account) }
  let(:product) { account.crm_products.create!(name: '10.4寸工业屏', sku: 'P.A') }

  before { pmc.account_users.first.update!(role: :administrator, mes_roles: %w[pmc engineer]) }

  def auth
    { api_access_token: pmc.access_token.token }
  end

  def production_order(line)
    account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品', qty: 1,
      stage: 'PRODUCTION', owner_id: pmc.id, product_line: line
    )
  end

  # BOM 与物料现在都校验产线必填，**空产线只会以历史数据的形式存在**（校验是后来加的，
  # 生产库里那些空产线的老行一条都没走过这道校验）。要测的正是这批老行，
  # 所以绕过校验直接把列清空——这是在造历史数据，不是在走业务路径。
  def bom(line)
    record = account.mes_boms.create!(bom_no: "B#{SecureRandom.hex(4)}", crm_product_id: product.id,
                                      owner_id: pmc.id, product_line: 'TABLET')
    record.update_column(:product_line, line) if line.nil? # rubocop:disable Rails/SkipsModelValidations
    record
  end

  def get_list(path, params = {})
    get "/api/v1/accounts/#{account.id}/mes/#{path}", params: params, headers: auth
    response.parsed_body
  end

  it '生产订单：切到具体产线时报出被隐藏的条数，列表本身不变' do
    production_order('TABLET')
    production_order(nil)
    production_order(nil)

    body = get_list('production_orders', { product_line: 'TABLET' })

    expect(body['meta']['count']).to eq(1)
    expect(body['meta']['hidden_no_line']).to eq(2)
    expect(body['payload'].size).to eq(1)
  end

  it '不切产线（全部产线）时不报隐藏数——那会儿什么都没被筛掉' do
    production_order('TABLET')
    production_order(nil)

    body = get_list('production_orders')

    expect(body['meta']['count']).to eq(2)
    expect(body['meta']['hidden_no_line']).to eq(0)
  end

  it 'BOM：同样报出被产线隐藏的条数' do
    bom('TABLET')
    bom(nil)

    body = get_list('boms', { product_line: 'TABLET' })

    expect(body['meta']['count']).to eq(1)
    expect(body['meta']['hidden_no_line']).to eq(1)
  end

  it 'BOM 模版：原来连 meta 都没有，现在也报隐藏数' do
    account.mes_bom_templates.create!(name: '平板模版', owner_id: pmc.id, product_line: 'TABLET')
    account.mes_bom_templates.create!(name: '无产线模版', owner_id: pmc.id, product_line: nil)

    body = get_list('bom_templates', { product_line: 'TABLET' })

    expect(body['payload'].size).to eq(1)
    expect(body['meta']['hidden_no_line']).to eq(1)
  end

  it '搜索命中为空时隐藏数也跟着为 0，不会报个与屏幕无关的数' do
    production_order(nil)

    body = get_list('production_orders', { product_line: 'TABLET', q: '对不上的关键字' })

    expect(body['meta']['count']).to eq(0)
    expect(body['meta']['hidden_no_line']).to eq(0)
  end
end
