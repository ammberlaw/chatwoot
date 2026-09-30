# frozen_string_literal: true

require 'rails_helper'

# MES 各处人名要带上岗位——「工程-朱桂权」「采购-何双双」。
# 光一个人名看不出该找哪个岗位的人催，尤其是跨部门催单的时候。
# 口径统一在 Mes::StaffNames：看板、单据详情、转发目标走同一套，不会分叉。
RSpec.describe 'MES 岗位显示', type: :request do
  let(:account) { create(:account) }
  let(:viewer) { create(:user, account: account) }
  let(:engineer) { create(:user, account: account, name: '朱桂权') }
  let(:buyer) { create(:user, account: account, name: '何双双') }
  let(:both) { create(:user, account: account, name: '熊莉莉') }
  let(:nobody) { create(:user, account: account, name: '路人') }

  before do
    engineer.account_users.first.update!(mes_role: 'engineer')
    buyer.account_users.first.update!(mes_role: 'buyer')
    both.account_users.first.update!(mes_roles: %w[pmc buyer])
    nobody.account_users.first.update!(mes_role: nil, mes_roles: [])
  end

  def auth
    { api_access_token: viewer.access_token.token }
  end

  def board(key, ids)
    Mes::BoardOwner.create!(account: account, board_key: key, product_line: '', manager_ids: ids)
  end

  def production_order(stage)
    account.mes_production_orders.create!(
      order_no: "MO#{SecureRandom.hex(4)}", product_name: '触摸显示器', qty: 1,
      stage: stage, approval_status: 'APPROVED', is_draft: false
    )
  end

  def waiting_for(stage)
    get "/api/v1/accounts/#{account.id}/mes/dashboard/pipeline", headers: auth
    response.parsed_body['stages'].find { |s| s['stage'] == stage }['cards'].first['waiting_names']
  end

  it '单岗位的人显示「岗位-姓名」' do
    board('mes_boms_index', [engineer.id])
    production_order('SALES_CONFIRMED')

    expect(waiting_for('SALES_CONFIRMED')).to eq(['工程-朱桂权'])
  end

  it '采购阶段显示采购岗' do
    board('mes_purchase_orders_index', [buyer.id])
    production_order('PURCHASING')

    expect(waiting_for('PURCHASING')).to eq(['采购-何双双'])
  end

  it '身兼两岗的人按板块显示对应岗位：BOM 列显 PMC' do
    board('mes_boms_index', [both.id])
    production_order('BOM_READY')

    expect(waiting_for('BOM_READY')).to eq(['PMC-熊莉莉'])
  end

  it '身兼两岗的人在采购列显采购，不是 PMC' do
    board('mes_purchase_orders_index', [both.id])
    production_order('PURCHASING')

    expect(waiting_for('PURCHASING')).to eq(['采购-熊莉莉'])
  end

  it '没配 MES 岗位的只显示姓名，不硬编一个岗位' do
    board('mes_boms_index', [nobody.id])
    production_order('BOM_READY')

    expect(waiting_for('BOM_READY')).to eq(['路人'])
  end

  it '同一阶段多个负责人各自带各自的岗位' do
    board('mes_boms_index', [engineer.id, both.id])
    production_order('BOM_READY')

    expect(waiting_for('BOM_READY')).to match_array(%w[工程-朱桂权 PMC-熊莉莉])
  end

  describe '生产订单详情' do
    it '阶段负责人与接单人都带岗位' do
      board('mes_boms_index', [engineer.id])
      po = production_order('BOM_READY')
      po.update!(stage_ack_by_id: engineer.id, stage_ack_at: Time.current)

      get "/api/v1/accounts/#{account.id}/mes/production_orders/#{po.id}", headers: auth

      body = response.parsed_body
      expect(body['stage_owner_names']).to eq(['工程-朱桂权'])
      expect(body['stage_ack_by_name']).to eq('工程-朱桂权')
      # 头像取姓名首字，所以 name 必须留纯姓名——否则工程岗的人头像全是「工」。
      expect(body['stage_owners']).to eq([{ 'id' => engineer.id, 'name' => '朱桂权', 'label' => '工程-朱桂权' }])
    end

    it '归属业务员没有 MES 岗位，只显示姓名不硬编岗位' do
      po = production_order('BOM_READY')
      po.update!(owner_id: nobody.id)

      get "/api/v1/accounts/#{account.id}/mes/production_orders/#{po.id}", headers: auth

      expect(response.parsed_body['owner_name']).to eq('路人')
    end

    it '转发目标列出的负责人也带岗位' do
      board('mes_purchase_orders_index', [buyer.id])
      po = production_order('BOM_READY')

      get "/api/v1/accounts/#{account.id}/mes/production_orders/#{po.id}", headers: auth

      target = response.parsed_body['forward_targets'].find { |t| t['board_key'] == 'mes_purchase_orders_index' }
      expect(target['recipient_names']).to eq(['采购-何双双'])
    end
  end

  describe Mes::StaffNames do
    subject(:staff) { described_class.new(account) }

    it '身兼两岗的人按场合挑岗位，挑不着就用第一个岗位' do
      expect(staff.for_user(both, described_class::PURCHASING)).to eq('采购-熊莉莉')
      expect(staff.for_user(both, described_class::ENGINEERING)).to eq('PMC-熊莉莉')
      expect(staff.for_user(both, described_class::WAREHOUSE)).to eq('PMC-熊莉莉')
    end

    it '批量转换保持传入顺序' do
      expect(staff.for_ids([buyer.id, engineer.id])).to eq(%w[采购-何双双 工程-朱桂权])
    end

    it '查不到的 id 跳过，不会塞进空值' do
      expect(staff.for_ids([engineer.id, -1])).to eq(['工程-朱桂权'])
    end

    it '没传人返回空，不炸' do
      expect(staff.for_ids(nil)).to eq([])
      expect(staff.for_user(nil)).to be_nil
    end
  end
end
