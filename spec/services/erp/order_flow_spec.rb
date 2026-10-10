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

  # 建单强制带附件（PI/生产订单）和订单类型，测试里塞占位值满足硬校验。
  def sales_order(status: 'IN_PRODUCTION', amount_micros: 100_000_000, currency: 'CNY', rate: 1, kind: 'CUSTOM')
    order = account.crm_sales_orders.new(
      name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
      status: status, order_kind: kind, crm_customer_id: customer.id, owner_id: user.id,
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

  # 物料 + 一张已提交采购单给它定价：材料成本按**最近一次采购单价**计，
  # 物料档 cost_price_micros 生产上一条都没维护、取出来恒等于 0
  # （见 Erp::CostRollupService#last_purchase_price），所以造数必须造采购单价。
  # 采购单不挂 production_order_id——挂了会被当成该单的外协加工费重复计一遍。
  def material(cost_micros)
    mat = account.mes_materials.create!(
      material_no: "M#{SecureRandom.hex(4)}", name: '原料', unit: 'PCS', cost_price_micros: cost_micros,
      product_line: 'TABLET'
    )
    priced_po(mat, cost_micros)
    mat
  end

  def priced_po(mat, rate_micros)
    po = account.mes_purchase_orders.create!(po_no: "PR#{SecureRandom.hex(4)}", status: 'SUBMITTED',
                                             owner_id: user.id, product_line: 'TABLET')
    po.purchase_items.create!(account_id: account.id, qty: 1, rate_micros: rate_micros,
                              mes_material_id: mat.id)
    po
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
      supplier = account.mes_suppliers.create!(name: '外协厂', product_line: 'TABLET')
      po = account.mes_purchase_orders.create!(po_no: "PU#{SecureRandom.hex(4)}", status: 'SUBMITTED',
                                               production_order_id: prod.id, owner_id: user.id,
                                               product_line: 'TABLET')
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
    # 以下用例测的都是「ERP 应收已启用」之后的行为，显式打开开关。
    # 过渡期（开关关着）的行为单独在下一个 describe 里测。
    before { Erp::Setting.create!(account: account, receivables_enabled: true) }

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

  # 金蝶过渡期：账还在金蝶，ERP 应收一条数据都没有。此时「收清」判不出来，
  # 出货即完结——否则每出一单就多卡一单在 SHIPPED，只能靠业务员手工改状态。
  describe '④ 过渡期（ERP 应收未启用）出货即完结' do
    it '已出货的订单直接判完结，不等应收台账' do
      order = sales_order(status: 'SHIPPED')

      expect(Erp::OrderCompletionService.new(account).sync!(order)).to be(true)
      expect(order.reload.status).to eq('COMPLETED')
    end

    it '还没出货的订单照样不动（不会跳过出货直接完结）' do
      order = sales_order(status: 'IN_PRODUCTION')

      expect(Erp::OrderCompletionService.new(account).sync!(order)).to be(false)
      expect(order.reload.status).to eq('IN_PRODUCTION')
    end

    it '开关一旦打开就立刻回到「收清才完结」的口径' do
      order = sales_order(status: 'SHIPPED')
      Erp::Setting.create!(account: account, receivables_enabled: true)

      expect(Erp::OrderCompletionService.new(account).sync!(order)).to be(false)
      expect(order.reload.status).to eq('SHIPPED')
    end
  end

  # 订单类型是过渡期的分流开关（定制→MES 生产单 / 库存→金蝶），空着下游无从分流。
  describe '⑤ 订单类型必填' do
    def new_order(kind)
      order = account.crm_sales_orders.new(
        name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
        status: 'IN_PRODUCTION', order_kind: kind, crm_customer_id: customer.id, owner_id: user.id
      )
      order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
      order
    end

    it '人工建单不选订单类型存不进去' do
      order = new_order(nil)

      expect(order.save).to be(false)
      expect(order.errors[:order_kind]).to include('请选择订单类型（定制单/库存单）')
    end

    it 'PI 付款自动转单等系统内转换豁免（系统猜不出是定制还是库存，猜错更糟）' do
      order = new_order(nil)
      order.system_generated = true

      expect(order.save).to be(true)
    end

    it '存量未分类的老单照常能改，不逼业务员回填历史' do
      order = new_order('CUSTOM')
      order.save!
      order.update_columns(order_kind: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(order.reload.update(remark: '改个备注')).to be(true)
    end
  end

  # 销售出库的成本结转凭证。原来这段**零测试覆盖**，于是一个硬断点在生产上躺了很久：
  # 成本只认挂在出库单名下的归集行，而定制单的成本是挂在生产订单上的，
  # 定制单因此永远结转不出成本——收入记了、成本没记，利润表毛利虚高。
  describe '⑥ 销售出库 → 成本结转凭证' do
    before do
      Erp::ChartOfAccountsService.ensure_standard!(account)
      Erp::AutoVoucherRule.ensure_defaults!(account)
    end

    def cost_voucher(shipment)
      account.erp_vouchers.find_by(source_type: 'Mes::Shipment::Cost', source_id: shipment.id)
    end

    def shipment_for(order, prod, kind: 'PRODUCTION')
      account.mes_shipments.create!(
        shipment_no: "DN#{SecureRandom.hex(4)}", kind: kind, status: 'DRAFT',
        crm_sales_order_id: order.id, production_order_id: prod&.id, owner_id: user.id,
        product_line: 'TABLET',
        shipment_items_attributes: [{ account_id: account.id, qty: 10 }]
      )
    end

    it '定制单出库要结转成本（成本挂在生产订单上，不在出库单上）' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10) # 30 元
      Erp::CostRollupService.new(account).for_sales_order(order)
      ship = shipment_for(order, prod)

      Erp::AutoVoucherService.new(account).for_shipment_cost(ship)

      voucher = cost_voucher(ship)
      expect(voucher).to be_present
      expect(voucher.lines.sum { |l| l.direction == 'DEBIT' ? l.base_amount_micros : 0 }).to eq(30_000_000)
      expect(voucher.lines.find { |l| l.direction == 'DEBIT' }.ledger_account.code).to eq('6401')
      expect(voucher.lines.find { |l| l.direction == 'CREDIT' }.ledger_account.code).to eq('1405')
    end

    it '成本口径与毛利表一致：手工补录的运费也结转进总账' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      Erp::CostRollupService.new(account).for_sales_order(order)
      account.erp_order_costs.create!(crm_sales_order_id: order.id, cost_type: 'FREIGHT',
                                      amount_micros: 8_000_000, currency: 'CNY', exchange_rate: 1)
      ship = shipment_for(order, prod)

      Erp::AutoVoucherService.new(account).for_shipment_cost(ship)

      expect(cost_voucher(ship).lines.sum { |l| l.direction == 'DEBIT' ? l.base_amount_micros : 0 })
        .to eq(38_000_000)
      # 毛利表的成本也必须是这个数——两边不同口径，利润表和毛利表就对不上。
      expect(Erp::MarginService.new(account).by_order.find { |r| r[:order_id] == order.id }[:cost_micros])
        .to eq(38_000_000)
    end

    it '分批发货整笔成本只结转一次，第二张出库单不再重复结转' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      Erp::CostRollupService.new(account).for_sales_order(order)
      first = shipment_for(order, prod)
      second = shipment_for(order, prod)

      service = Erp::AutoVoucherService.new(account)
      service.for_shipment_cost(first)
      service.for_shipment_cost(second)

      expect(cost_voucher(first)).to be_present
      expect(cost_voucher(second)).to be_nil
    end

    it '重复调用不会出第二张凭证（幂等）' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      Erp::CostRollupService.new(account).for_sales_order(order)
      ship = shipment_for(order, prod)

      service = Erp::AutoVoucherService.new(account)
      3.times { service.for_shipment_cost(ship) }

      expect(account.erp_vouchers.where(source_type: 'Mes::Shipment::Cost', source_id: ship.id).count).to eq(1)
    end

    it '一分钱成本都没归集到就不出凭证（宁可没有也不出一张金额为 0 的）' do
      order = sales_order
      prod = production_order(order)
      ship = shipment_for(order, prod)

      Erp::AutoVoucherService.new(account).for_shipment_cost(ship)

      expect(cost_voucher(ship)).to be_nil
    end

    it '现货单照旧按出库单自己的 FIFO 成本结转（没挂销售订单的也认）' do
      order = sales_order
      ship = shipment_for(order, nil, kind: 'STOCK')
      account.erp_order_costs.create!(crm_sales_order_id: order.id, source_type: 'Mes::Shipment',
                                      source_id: ship.id, cost_type: 'MATERIAL',
                                      amount_micros: 12_000_000, currency: 'CNY', exchange_rate: 1)

      Erp::AutoVoucherService.new(account).for_shipment_cost(ship)

      expect(cost_voucher(ship).lines.sum { |l| l.direction == 'DEBIT' ? l.base_amount_micros : 0 })
        .to eq(12_000_000)
    end

    # 生产实测：订单软删后 default_scope 把它过滤掉，shipment.crm_sales_order 读成 nil。
    # 原来这里直接 order.id 取防重用的订单号，补数任务上就炸了 undefined method 'id' for nil。
    it '订单已软删就不结转成本（收入凭证也不会出，只记成本会让总账单边）' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      Erp::CostRollupService.new(account).for_sales_order(order)
      ship = shipment_for(order, prod)
      order.soft_delete!(user)

      service = Erp::AutoVoucherService.new(account)
      expect { service.for_shipment_cost(ship.reload) }.not_to raise_error
      expect(cost_voucher(ship)).to be_nil
    end

    it '关掉 SHIPMENT_COST 开关就不出凭证' do
      order = sales_order
      prod = production_order(order)
      issue_entry(prod, material(3_000_000), 10)
      Erp::CostRollupService.new(account).for_sales_order(order)
      account.erp_auto_voucher_rules.find_by(event_key: 'SHIPMENT_COST').update!(is_active: false)
      ship = shipment_for(order, prod)

      Erp::AutoVoucherService.new(account).for_shipment_cost(ship)

      expect(cost_voucher(ship)).to be_nil
    end
  end
end
