# frozen_string_literal: true

require 'rails_helper'

# CRM → MES → ERP 主链路上的三个自动化断点：
#   1. 成本归集：MES 的领料/外协采购要自动变成 ERP 订单成本（此前纯手工录，毛利表全靠人维护）
#   2. 应收漏建账：已确认订单没建应收要能被发现（此前静默漏账，报表少一笔无任何提示）
#   3. 订单完结：已出货 + 已收清 → COMPLETED（此前没人推，订单永远停在 SHIPPED）
#
# 这三条都是**自动触发**的，出错时没有报错、只有数字悄悄不对，所以必须有断言兜着。
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'CRM→MES→ERP 订单流转' do
  # rubocop:enable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }

  # 建单强制带附件（PI/生产订单），测试里塞一个占位附件满足硬校验。
  def sales_order(status: 'IN_PRODUCTION', amount_micros: 100_000_000, currency: 'CNY', rate: 1)
    order = account.crm_sales_orders.new(
      name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
      status: status, crm_customer_id: customer.id, owner_id: user.id,
      order_amount_micros: amount_micros, order_currency: currency, exchange_rate: rate
    )
    order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!
    order
  end

  def production_order(order, outsourced: false, stage: 'PRODUCTION')
    account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品A', qty: 10,
      crm_sales_order_id: order.id, stage: stage, is_outsourced: outsourced, owner_id: user.id
    )
  end

  def material(cost_micros)
    account.mes_materials.create!(
      material_no: "M#{SecureRandom.hex(4)}", name: '原料', unit: 'PCS', cost_price_micros: cost_micros
    )
  end

  # 直接落 POSTED：过账动作会去刷结存/推进阶段，这里只关心成本归集读到的数。
  def issue_entry(prod_order, mat, qty, purpose: 'MATERIAL_ISSUE')
    entry = account.mes_stock_entries.create!(
      entry_no: "SE#{SecureRandom.hex(4)}", purpose: purpose, status: 'POSTED',
      production_order_id: prod_order.id, owner_id: user.id
    )
    entry.stock_entry_items.create!(account_id: account.id, item_type: 'MATERIAL',
                                    mes_material_id: mat.id, qty: qty)
    entry
  end

  describe '① 订单成本自动归集' do
    it '自产单按领料算材料成本（数量 × 物料成本价）' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10) # 10 × 3元 = 30元

      Erp::CostRollupService.new(account).for_sales_order(order)

      cost = account.erp_order_costs.find_by(source_type: 'Mes::ProductionOrder', source_id: prod.id)
      expect(cost.cost_type).to eq('MATERIAL')
      expect(cost.amount_micros).to eq(30_000_000)
    end

    it '退料要从成本里扣掉，不能只加不减' do
      order = sales_order
      prod = production_order(order)
      mat = material(3_000_000)
      issue_entry(prod, mat, 10)
      issue_entry(prod, mat, 4, purpose: 'MATERIAL_RETURN') # 退 4 → 净耗 6

      Erp::CostRollupService.new(account).for_sales_order(order)

      expect(account.erp_order_costs.find_by(source_id: prod.id).amount_micros).to eq(18_000_000)
    end

    it '重复归集不会翻倍（幂等），金额变了则更新' do
      order = sales_order
      prod = production_order(order)
      mat = material(3_000_000)
      issue_entry(prod, mat, 10)

      service = Erp::CostRollupService.new(account)
      3.times { service.for_sales_order(order) }
      expect(account.erp_order_costs.where(source_id: prod.id).count).to eq(1)

      issue_entry(prod, mat, 5) # 再领 5
      service.for_sales_order(order)
      expect(account.erp_order_costs.find_by(source_id: prod.id).amount_micros).to eq(45_000_000)
    end

    it '外协单按采购单算加工成本，且不会因为收货入库被重复计一遍材料' do
      order = sales_order
      prod = production_order(order, outsourced: true)
      supplier = account.mes_suppliers.create!(name: '外协厂')
      po = account.mes_purchase_orders.create!(po_no: "PU#{SecureRandom.hex(4)}", status: 'SUBMITTED',
                                               production_order_id: prod.id, owner_id: user.id)
      po.purchase_items.create!(account_id: account.id, qty: 10, rate_micros: 5_000_000,
                                mes_supplier_id: supplier.id)
      # 外协件收货入库：若归集口径没分流，这批料会被再算一次
      issue_entry(prod, material(5_000_000), 10, purpose: 'MATERIAL_RECEIPT')

      Erp::CostRollupService.new(account).for_sales_order(order)

      costs = account.erp_order_costs.where(crm_sales_order_id: order.id)
      expect(costs.count).to eq(1)
      expect(costs.first.cost_type).to eq('PROCESS')
      expect(costs.first.amount_micros).to eq(50_000_000)
    end

    it '手工录入的成本行不会被自动归集冲掉' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      manual = account.erp_order_costs.create!(crm_sales_order_id: order.id, cost_type: 'FREIGHT',
                                               amount_micros: 8_000_000, currency: 'CNY', exchange_rate: 1)

      Erp::CostRollupService.new(account).for_sales_order(order)

      expect(manual.reload).to be_persisted
      expect(account.erp_order_costs.where(crm_sales_order_id: order.id).count).to eq(2)
    end

    it '生产订单进「销售出库」阶段时自动归集，不用等人点按钮' do
      order = sales_order
      prod = production_order(order, stage: 'FG_INBOUND')
      issue_entry(prod, material(3_000_000), 10)

      prod.enter_stage!('SHIPPED')

      expect(account.erp_order_costs.find_by(source_id: prod.id)&.amount_micros).to eq(30_000_000)
    end

    it 'ERP 归集炸了也不能挡住 MES 推进阶段（出不了货比记不上账严重）' do
      order = sales_order
      prod = production_order(order, stage: 'FG_INBOUND')
      allow(Erp::CostRollupService).to receive(:new).and_raise(StandardError, '模拟归集异常')

      expect { prod.enter_stage!('SHIPPED') }.not_to raise_error
      expect(prod.reload.stage).to eq('SHIPPED')
    end

    it '全部退料后成本归零，旧的成本行要被清掉而不是留着' do
      order = sales_order
      prod = production_order(order)
      mat = material(3_000_000)
      issue_entry(prod, mat, 10)
      service = Erp::CostRollupService.new(account)
      service.for_sales_order(order)

      issue_entry(prod, mat, 10, purpose: 'MATERIAL_RETURN')
      service.for_sales_order(order)

      expect(account.erp_order_costs.where(source_id: prod.id)).to be_empty
    end
  end

  describe '② 应收待建账清单' do
    let(:controller_scope) do
      lambda do
        built = account.erp_receivables.where.not(crm_sales_order_id: nil).select(:crm_sales_order_id)
        account.crm_sales_orders.where.not(status: %w[PENDING_CONFIRMATION CANCELLED]).where.not(id: built)
      end
    end

    it '已确认且没建应收的订单会被列出来' do
      order = sales_order
      expect(controller_scope.call).to include(order)
    end

    it '建过账的订单不再出现在待建账里' do
      order = sales_order
      Erp::LedgerBuilderService.new(account).from_sales_order(order)
      expect(controller_scope.call).not_to include(order)
    end

    it '未确认/已取消的订单不该进应收待办' do
      pending_order = sales_order(status: 'PENDING_CONFIRMATION')
      cancelled = sales_order(status: 'CANCELLED')
      expect(controller_scope.call).not_to include(pending_order, cancelled)
    end
  end

  describe '③ 销售订单自动完结' do
    def receipt_for(ledger, amount_micros)
      receipt = account.erp_receipt_records.create!(
        receipt_no: "RC#{SecureRandom.hex(4)}", crm_customer_id: customer.id, amount_micros: amount_micros,
        currency: 'CNY', exchange_rate: 1, received_at: Time.zone.today
      )
      Erp::AllocationService.new(receipt, :receipt).apply!([{ ledger_id: ledger.id, amount_micros: amount_micros }])
      receipt
    end

    it '已出货 + 收款核销收清 → 自动完结' do
      order = sales_order(status: 'SHIPPED')
      ledger = Erp::LedgerBuilderService.new(account).from_sales_order(order)
      receipt_for(ledger, 100_000_000)

      expect(order.reload.status).to eq('COMPLETED')
    end

    it '只收了一部分不算完结' do
      order = sales_order(status: 'SHIPPED')
      ledger = Erp::LedgerBuilderService.new(account).from_sales_order(order)
      receipt_for(ledger, 40_000_000)

      expect(order.reload.status).to eq('SHIPPED')
    end

    it '还没出货就收清了不会跳过出货直接完结' do
      order = sales_order(status: 'IN_PRODUCTION')
      ledger = Erp::LedgerBuilderService.new(account).from_sales_order(order)
      receipt_for(ledger, 100_000_000)

      expect(order.reload.status).to eq('IN_PRODUCTION')
    end

    it '收款单作废后订单要退回已出货，不能还挂着「已完结」' do
      order = sales_order(status: 'SHIPPED')
      ledger = Erp::LedgerBuilderService.new(account).from_sales_order(order)
      receipt = receipt_for(ledger, 100_000_000)
      expect(order.reload.status).to eq('COMPLETED')

      Erp::AllocationService.new(receipt, :receipt).void!

      expect(order.reload.status).to eq('SHIPPED')
    end

    it '没建应收台账的订单不会被判成完结（漏建账不该被悄悄标成已完结）' do
      order = sales_order(status: 'SHIPPED')
      Erp::OrderCompletionService.new(account).sync!(order)

      expect(order.reload.status).to eq('SHIPPED')
    end
  end
end
