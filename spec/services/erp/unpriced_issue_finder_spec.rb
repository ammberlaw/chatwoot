# frozen_string_literal: true

require 'rails_helper'

# 「按 0 计价的料」清单。
#
# 成本归集按最近一次采购单价给领料计价，查不到价就按 0 计——不报错、不留痕，
# 毛利表只是悄悄偏高。这张清单是「少算在哪」的唯一出口，口径必须和成本归集完全一致：
# 这里报缺价的，就是那边真按 0 算的那批料，不能多也不能少。
RSpec.describe Erp::UnpricedIssueFinder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }

  def sales_order
    order = account.crm_sales_orders.new(
      name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: Time.zone.today,
      status: 'IN_PRODUCTION', order_kind: 'CUSTOM', crm_customer_id: customer.id, owner_id: user.id,
      order_amount_micros: 100_000_000, order_currency: 'CNY', exchange_rate: 1
    )
    order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!
    order
  end

  def production_order(order)
    account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '成品A', qty: 10,
      crm_sales_order_id: order.id, stage: 'PRODUCTION', owner_id: user.id
    )
  end

  def material(name)
    account.mes_materials.create!(material_no: "M-#{name}", name: name, unit: 'PCS', product_line: 'TABLET')
  end

  def priced!(mat, rate_micros, status: 'SUBMITTED')
    po = account.mes_purchase_orders.create!(po_no: "PR#{SecureRandom.hex(4)}", status: status,
                                             owner_id: user.id, product_line: 'TABLET')
    po.purchase_items.create!(account_id: account.id, qty: 1, rate_micros: rate_micros, mes_material_id: mat.id)
  end

  def issue!(prod, mat, qty, purpose: 'MATERIAL_ISSUE')
    entry = account.mes_stock_entries.create!(
      entry_no: "SE#{SecureRandom.hex(4)}", purpose: purpose, status: 'POSTED',
      production_order_id: prod.id, owner_id: user.id
    )
    entry.stock_entry_items.create!(account_id: account.id, item_type: 'MATERIAL',
                                    mes_material_id: mat.id, qty: qty)
  end

  it '报出从没采购过因而按 0 计价的料，带上领用量与牵涉订单数' do
    prod = production_order(sales_order)
    issue!(prod, material('屏'), 10)

    result = described_class.new(account).perform

    expect(result[:count]).to eq(1)
    expect(result[:rows].first).to include(code: 'M-屏', name: '屏', qty: 10.0, order_count: 1)
  end

  it '有采购价的料不进清单' do
    prod = production_order(sales_order)
    priced!(material('主板').tap { |m| issue!(prod, m, 5) }, 8_000_000)

    expect(described_class.new(account).perform[:count]).to eq(0)
  end

  it '只有草稿采购单的料仍算缺价（与成本归集的采购单状态口径一致）' do
    prod = production_order(sales_order)
    mat = material('外壳')
    issue!(prod, mat, 3)
    priced!(mat, 2_000_000, status: 'DRAFT')

    expect(described_class.new(account).perform[:count]).to eq(1)
  end

  it '采购单填了 0 价等于没价，照样算缺价' do
    prod = production_order(sales_order)
    mat = material('螺丝')
    issue!(prod, mat, 100)
    priced!(mat, 0)

    expect(described_class.new(account).perform[:count]).to eq(1)
  end

  it '同一颗料被多张订单领用时合成一行，按订单数计' do
    mat = material('电池')
    2.times { issue!(production_order(sales_order), mat, 4) }

    rows = described_class.new(account).perform[:rows]
    expect(rows.size).to eq(1)
    expect(rows.first[:order_count]).to eq(2)
    expect(rows.first[:qty]).to eq(8.0)
  end

  it '没挂销售订单的生产订单不算（成本归集本来也不处理）' do
    prod = account.mes_production_orders.create!(
      order_no: "PO#{SecureRandom.hex(4)}", product_name: '散单', qty: 1,
      stage: 'PRODUCTION', owner_id: user.id
    )
    issue!(prod, material('边角料'), 1)

    expect(described_class.new(account).perform[:count]).to eq(0)
  end

  it '未过账的领料单不算（成本归集只认已过账）' do
    prod = production_order(sales_order)
    mat = material('草稿料')
    entry = account.mes_stock_entries.create!(
      entry_no: "SE#{SecureRandom.hex(4)}", purpose: 'MATERIAL_ISSUE', status: 'DRAFT',
      production_order_id: prod.id, owner_id: user.id
    )
    entry.stock_entry_items.create!(account_id: account.id, item_type: 'MATERIAL',
                                    mes_material_id: mat.id, qty: 9)

    expect(described_class.new(account).perform[:count]).to eq(0)
  end
end
