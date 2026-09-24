# frozen_string_literal: true

require 'rails_helper'

# 阶段内接力：工程与 PMC 同为「工程/PMC BOM」阶段负责人，一个阶段要能两人先后各接一次。
#
# 原来接单状态只在订单上存一份，后接的人会把前一个人覆盖掉——工程出完 BOM 转给 PMC 投单
# 这种实际走法，账面上只剩一个接单人，前后顺序和工作量都看不出来。
RSpec.describe Mes::ProductionOrder do
  let(:account) { create(:account) }
  let(:engineer) { create(:user, account: account, name: '工程') }
  let(:pmc) { create(:user, account: account, name: 'PMC') }
  let(:outsider) { create(:user, account: account, name: '路人') }

  before do
    # 两人同为 BOM 阶段负责人（与生产上「熊莉莉、魏伟超」同一种配置）
    Mes::BoardOwner.create!(account: account, board_key: 'mes_boms_index', product_line: '',
                            manager_ids: [engineer.id, pmc.id])
  end

  def order
    @order ||= account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品A', qty: 10,
      stage: 'SALES_CONFIRMED', owner_id: engineer.id, approval_status: 'APPROVED'
    )
  end

  it '工程接单后转给 PMC：接单状态清空，PMC 那边重新变成待接单' do
    order.acknowledge!(engineer)
    expect(order.stage_ack_at).to be_present

    order.handoff_stage!(actor: engineer, to_user: pmc, note: '换了电池，按新 BOM 投')

    expect(order.reload.stage_ack_at).to be_nil
    expect(order.awaiting_ack?).to be(true)
  end

  it '两人各自的接单记录都留下来，顺序可查' do
    order.acknowledge!(engineer)
    order.handoff_stage!(actor: engineer, to_user: pmc)
    order.acknowledge!(pmc)

    log = order.stage_ack_events.chronological.map { |e| [e.kind, e.actor.name, e.to_user&.name] }
    expect(log).to eq([
                        ['ACK', '工程', nil],
                        ['HANDOFF', '工程', 'PMC'],
                        ['ACK', 'PMC', nil]
                      ])
  end

  it '允许反向转回（PMC 接了才发现要改料）' do
    order.acknowledge!(pmc)
    expect { order.handoff_stage!(actor: pmc, to_user: engineer) }.not_to raise_error
    expect(order.stage_ack_events.where(kind: 'HANDOFF').last.to_user_id).to eq(engineer.id)
  end

  it '不能转给本阶段以外的人，也不能转给自己' do
    expect { order.handoff_stage!(actor: engineer, to_user: outsider) }
      .to raise_error(StandardError, /本阶段的另一位负责人/)
    expect { order.handoff_stage!(actor: engineer, to_user: engineer) }
      .to raise_error(StandardError, /不能转给自己/)
  end

  it '非本阶段负责人不能发起转交' do
    expect { order.handoff_stage!(actor: outsider, to_user: pmc) }
      .to raise_error(StandardError, /只有本阶段负责人/)
  end

  it '转交不重置超时计时——否则来回转一次就能把超时洗白' do
    before_deadline = order.ack_deadline
    order.acknowledge!(engineer)
    order.handoff_stage!(actor: engineer, to_user: pmc)
    expect(order.reload.ack_deadline).to eq(before_deadline)
  end
end
