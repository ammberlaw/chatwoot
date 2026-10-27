# frozen_string_literal: true

require 'rails_helper'

# 「有权代办」≠「分配给我」。
#
# 副管理员/管理员对别人的单有兜底代办权（能点确认），但那是代办能力，
# 不是把这件事派给了他。两者混用，副管的待办里就会躺满全公司每个业务员的
# 用料确认（2026-10-27 生产实证 WT-20261026-01）。用户原话：
# 「不是自己的订单，不应进入自己的待办」。
#
# 待办列表、角标、推送复核（Mes::TodoPushJob 拿 TodoList 当准绳）都走同一对判定，
# 所以这份 spec 守住的是这四处。
RSpec.describe 'MES 待办分配口径', type: :model do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, name: '归属业务员') }
  let(:deputy) { create(:user, account: account, name: '副管理员') }
  let(:admin) { create(:user, account: account, name: '管理员') }

  let(:owner_au) { owner.account_users.first }
  let(:deputy_au) { deputy.account_users.first }
  let(:admin_au) { admin.account_users.first }

  before do
    deputy_au.update!(crm_role: 'deputy_admin')
    admin_au.update!(role: 'administrator')
  end

  def todo_action_types(account_user)
    Mes::TodoList.new(account: account, account_user: account_user)
                 .items.select { |i| i[:subject_id] == order.id }.pluck(:action_type)
  end

  describe '确认用料' do
    let!(:order) do
      account.mes_production_orders.create!(
        order_no: "MO#{SecureRandom.hex(4)}", product_name: '三防加固平板', qty: 1,
        stage: 'BOM_READY', approval_status: 'APPROVED', is_draft: false,
        order_kind: 'CUSTOMER', owner_id: owner.id,
        bom: account.mes_boms.create!(bom_no: "BOM#{SecureRandom.hex(4)}", base_qty: 1, product_line: '平板线')
      )
    end

    it '只进归属业务员的待办' do
      expect(todo_action_types(owner_au)).to include('confirm_bom')
    end

    it '不进副管理员和管理员的待办' do
      expect(todo_action_types(deputy_au)).not_to include('confirm_bom')
      expect(todo_action_types(admin_au)).not_to include('confirm_bom')
    end

    it '但副管理员和管理员仍然能代办（按钮照常亮）' do
      expect(order.can_confirm_bom?(deputy_au)).to be true
      expect(order.can_confirm_bom?(admin_au)).to be true
    end
  end

  describe '退回确认' do
    let!(:order) do
      account.mes_production_orders.create!(
        order_no: "MO#{SecureRandom.hex(4)}", product_name: '商显一体机', qty: 1,
        stage: 'BOM_READY', approval_status: 'APPROVED', is_draft: false,
        order_kind: 'CUSTOMER', owner_id: owner.id,
        sales_return_at: Time.current, sales_return_reason: '客户改了尺寸'
      )
    end

    it '只进归属业务员的待办，副管/管理员不进但仍能代办' do
      expect(todo_action_types(owner_au)).to include('sales_return_confirm')
      expect(todo_action_types(deputy_au)).not_to include('sales_return_confirm')
      expect(todo_action_types(admin_au)).not_to include('sales_return_confirm')

      expect(order.can_resolve_sales_return?(deputy_au)).to be true
    end
  end
end
