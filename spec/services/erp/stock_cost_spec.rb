require 'rails_helper'

# 成品 FIFO 存货核算：只测「算钱的地方」的硬恒等式（与 ERP 其余测试同哲学）。
# 存货成本算错是静默的——毛利表照样出数，只是数不对，不测就得等对账才发现。
RSpec.describe Erp::StockCostService do
  let(:account) { create(:account) }
  let(:warehouse) { Mes::Warehouse.create!(account: account, name: '成品仓', code: "WH#{SecureRandom.hex(3)}") }
  let(:product) do
    Crm::Product.create!(account: account, name: '平板 V2', sku: "SKU#{SecureRandom.hex(3)}", category: 'FINISHED')
  end
  let(:service) { described_class.new(account) }

  # MES 物理结存：批次层是 ERP 的成本账，实物结存是 MES 的——出库要过 MES 那道充足性校验。
  def seed_physical_stock!(qty)
    Mes::StockBalance.apply!(
      account_id: account.id, item_type: 'PRODUCT', warehouse_id: warehouse.id,
      mes_material_id: nil, crm_product_id: product.id, delta: qty
    )
  end

  # 两批不同进价：10 件 @800、30 件 @900（后进）
  def seed_layers!
    service.open_layer!(crm_product_id: product.id, warehouse_id: warehouse.id, qty: 10,
                        unit_cost_micros: 800 * 1_000_000, received_at: 10.days.ago)
    service.open_layer!(crm_product_id: product.id, warehouse_id: warehouse.id, qty: 30,
                        unit_cost_micros: 900 * 1_000_000, received_at: 3.days.ago)
    seed_physical_stock!(40)
  end

  def ship!(qty)
    entry = account.mes_stock_entries.create!(
      purpose: 'SHIPMENT', from_warehouse_id: warehouse.id,
      stock_entry_items_attributes: [
        { item_type: 'PRODUCT', crm_product_id: product.id, qty: qty, warehouse_id: warehouse.id }
      ]
    )
    entry.post!
    entry
  end

  def cogs_of(entry)
    account.erp_stock_consumptions.where(mes_stock_entry_id: entry.id).sum(:base_amount_micros)
  end

  describe '先进先出消耗' do
    before { seed_layers! }

    it '单层内出库按该层单价算成本' do
      expect(cogs_of(ship!(4))).to eq(4 * 800 * 1_000_000)
    end

    it '跨层出库按进货先后分段计价（不是平均价）' do
      # 12 件 = 先吃完 10@800 再取 2@900 = 8000 + 1800 = 9800
      expect(cogs_of(ship!(12))).to eq(9800 * 1_000_000)
      # 若按移动加权（均价 875）会是 10500——两种算法必须能区分开
      expect(cogs_of(account.mes_stock_entries.last)).not_to eq(12 * 875 * 1_000_000)
    end

    it '耗尽的层不再参与后续出库' do
      ship!(10)
      expect(cogs_of(ship!(5))).to eq(5 * 900 * 1_000_000)
    end

    it '层不足时不拦出库，只按已有层计价' do
      # 实物有 45（比批次层多 5：期初漏导的那种情况），发 45 件
      # → 成本只算得出有层的 40 件，差额留 0，存货页能看出缺口
      seed_physical_stock!(5)
      expect(cogs_of(ship!(45))).to eq((10 * 800 + 30 * 900) * 1_000_000)
    end
  end

  describe '作废回滚' do
    before { seed_layers! }

    it '出库作废把货原样还回原来那几层' do
      entry = ship!(12)
      entry.cancel!
      remaining = account.erp_stock_layers.order(:received_at).pluck(:qty_remaining)
      expect(remaining.map(&:to_i)).to eq([10, 30])
      expect(account.erp_stock_consumptions.where(mes_stock_entry_id: entry.id).count).to eq(0)
    end

    it '作废后再发货，成本与首次一致（层状态完全复原）' do
      first = ship!(12)
      amount = cogs_of(first)
      first.cancel!
      expect(cogs_of(ship!(12))).to eq(amount)
    end
  end

  describe '入库建层' do
    it '外购成品收货按采购行单价建层' do
      supplier = Mes::Supplier.create!(account: account, name: '供应商A', product_line: 'TABLET',
                                       supplier_no: "S#{SecureRandom.hex(3)}")
      po = account.mes_purchase_orders.create!(po_no: "PU#{SecureRandom.hex(4)}", status: 'SUBMITTED',
                                               approval_status: 'APPROVED', product_line: 'TABLET')
      # 金额由 单价×数量 自动算（compute_amount），所以给单价：850 × 20 = 17000
      po.purchase_items.create!(account: account, item_type: 'PRODUCT', crm_product_id: product.id,
                                mes_supplier_id: supplier.id, qty: 20, rate_micros: 850 * 1_000_000)
      entry = account.mes_stock_entries.create!(
        purpose: 'MATERIAL_RECEIPT', purchase_order: po, to_warehouse_id: warehouse.id,
        stock_entry_items_attributes: [
          { item_type: 'PRODUCT', crm_product_id: product.id, qty: 20, warehouse_id: warehouse.id }
        ]
      )
      entry.post!
      layer = account.erp_stock_layers.last
      # 17000 / 20 = 850
      expect(layer.unit_cost_micros).to eq(850 * 1_000_000)
      expect(layer.qty_remaining.to_i).to eq(20)
    end
  end
end
