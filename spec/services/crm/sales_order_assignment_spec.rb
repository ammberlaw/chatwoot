# frozen_string_literal: true

require 'rails_helper'

# 销售订单审核：「能点通过」≠「派给我审」。
#
# 管理员/副管对任何一张都能点（代办能力），但待办和角标只该装真正路由到他们的那些：
# 业务员所在团队没设负责人、或负责人就是他本人。口径必须与 notify_ids 一致——
# 两边分叉就会出现「角标 5 条、手机只推 2 条」（2026-10-27 生产实查正是 5 vs 2）。
RSpec.describe Crm::SalesOrderApprover do
  let(:account) { create(:account) }
  let(:lead) { create(:user, account: account, name: '团队负责人') }
  let(:member) { create(:user, account: account, name: '团队成员') }
  let(:loner) { create(:user, account: account, name: '没带团队的业务员') }
  let(:deputy) { create(:user, account: account, name: '副管理员') }

  let(:team) { account.crm_teams.create!(name: '外贸一组', team_lead_id: lead.id) }

  before do
    deputy.account_users.first.update!(crm_role: 'deputy_admin')
    member.account_users.first.update!(crm_role: 'sales', crm_team_id: team.id)
    lead.account_users.first.update!(crm_role: 'sales', crm_team_id: team.id)
    loner.account_users.first.update!(crm_role: 'sales', crm_team_id: nil)
  end

  # 跳过校验建单：这里测的是「这张单派给谁审」的取数口径，与建单必填项（附件/明细/
  # 结算方式等）无关；带全那些字段只会让这份 spec 跟着表单规则一起漂。
  def pending_order(owner)
    order = account.crm_sales_orders.new(
      order_no: "SO#{SecureRandom.hex(4)}", name: '测试订单', owner_id: owner.id,
      approval_status: 'PENDING', order_date: Time.zone.today
    )
    order.save(validate: false)
    order
  end

  def pending_for(user)
    described_class.pending_scope(account, user.account_users.first).pluck(:id)
  end

  it '有团队负责人的单：落负责人，不落副管' do
    order = pending_order(member)

    expect(pending_for(lead)).to include(order.id)
    expect(pending_for(deputy)).not_to include(order.id)
  end

  it '没带团队的业务员的单：落副管（没有更上一级可批）' do
    order = pending_order(loner)

    expect(pending_for(deputy)).to include(order.id)
  end

  it '负责人自己的单：他审不了自己，落副管' do
    order = pending_order(lead)

    expect(pending_for(lead)).not_to include(order.id)
    expect(pending_for(deputy)).to include(order.id)
  end

  it '代办能力不受影响：副管对别人团队的单照样能点通过' do
    order = pending_order(member)

    expect(described_class.can?(deputy.account_users.first, order)).to be true
  end

  it '与 notify_ids 同口径：待办里有谁，通知就发给谁' do
    [member, loner, lead].each do |owner|
      order = pending_order(owner)
      notified = described_class.notify_ids(account, order)

      account.account_users.includes(:user).each do |au|
        in_todo = described_class.pending_scope(account, au).exists?(id: order.id)
        expect(in_todo).to eq(notified.include?(au.user_id)),
                           "#{au.user.name} 对 #{owner.name} 的单：待办=#{in_todo} 通知=#{notified.include?(au.user_id)}"
      end
    end
  end
end
