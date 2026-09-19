# frozen_string_literal: true

require 'rails_helper'

# 订单页回款进度条（ERP_SPEC §2.5）。两条硬线：
#   1. 分期欠款口径必须与催收预警/账龄分析一致——业务员在订单页看到的数，
#      和财务催他的数不一样，这条功能就是负资产。
#   2. 只透出回款，成本/应付/毛利一个字段都不能出现在 payload 里。
RSpec.describe Erp::OrderReceivableProgress do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }
  let(:today) { Time.zone.today }

  def sales_order
    order = account.crm_sales_orders.new(
      name: '测试订单', order_no: "SO#{SecureRandom.hex(4)}", order_date: today,
      status: 'IN_PRODUCTION', crm_customer_id: customer.id, owner_id: user.id,
      order_amount_micros: 10_000 * 1_000_000, order_currency: 'CNY', exchange_rate: 1
    )
    order.files.attach(io: StringIO.new('PI'), filename: 'pi.pdf', content_type: 'application/pdf')
    order.save!
    order
  end

  # 10000 的单：订金 3000（30 天前到期）+ 尾款 7000（11 天后到期）
  def receivable_for(order, received: 0, currency: 'CNY', rate: 1)
    receivable = account.erp_receivables.create!(
      receivable_no: "AR-#{SecureRandom.hex(4)}", crm_customer: customer, crm_sales_order_id: order.id,
      currency: currency, exchange_rate: rate,
      total_amount_micros: 10_000 * 1_000_000,
      received_amount_micros: received * 1_000_000,
      status: received.zero? ? 'UNPAID' : 'PARTIAL'
    )
    receivable.installments.create!(account: account, seq: 1, kind: 'DEPOSIT', due_basis: 'FIXED',
                                    amount_micros: 3_000 * 1_000_000, due_date: today - 30)
    receivable.installments.create!(account: account, seq: 2, kind: 'BALANCE', due_basis: 'FIXED',
                                    amount_micros: 7_000 * 1_000_000, due_date: today + 11)
    receivable
  end

  def progress(order)
    described_class.new(order.reload).call
  end

  around do |example|
    ClimateControl.modify(ERP_ENABLED: 'true') { example.run }
  end

  it 'ERP 总开关关着时返回 nil——ERP 没上线，订单页不该出现这块' do
    order = sales_order
    receivable_for(order)
    ClimateControl.modify(ERP_ENABLED: 'false') { expect(progress(order)).to be_nil }
  end

  it '财务还没给这张订单建账时返回 nil，不是报错也不是 0' do
    expect(progress(sales_order)).to be_nil
  end

  it '一分钱没收：未收=全额，进度 0%' do
    order = sales_order
    receivable_for(order)
    result = progress(order)
    expect(result[:total_micros]).to eq(10_000 * 1_000_000)
    expect(result[:received_micros]).to be_zero
    expect(result[:outstanding_micros]).to eq(10_000 * 1_000_000)
    expect(result[:received_percent]).to be_zero
    expect(result[:status_label]).to eq('未收款')
  end

  it '已收款按到期日 FIFO 冲抵分期：收了 3000 就是订金收清，不是两期各摊一点' do
    order = sales_order
    receivable_for(order, received: 3_000)
    rows = progress(order)[:installments]
    expect(rows.map { |r| r[:kind_label] }).to eq(%w[订金 尾款])
    expect(rows.first).to include(received_micros: 3_000 * 1_000_000, outstanding_micros: 0, status: 'SETTLED')
    expect(rows.second).to include(received_micros: 0, outstanding_micros: 7_000 * 1_000_000)
  end

  it '订金逾期未收时这一期标 OVERDUE 并给出逾期天数' do
    order = sales_order
    receivable_for(order)
    deposit = progress(order)[:installments].first
    expect(deposit[:status]).to eq('OVERDUE')
    expect(deposit[:days]).to eq(30)
  end

  it '下一期到期日 = 最早的、还欠钱的那一期；订金收清后自动顺延到尾款' do
    order = sales_order
    receivable = receivable_for(order)
    expect(progress(order)[:next_due]).to include(kind_label: '订金', due_date: today - 30)

    receivable.update!(received_amount_micros: 3_000 * 1_000_000, status: 'PARTIAL')
    expect(progress(order)[:next_due]).to include(kind_label: '尾款', due_date: today + 11,
                                                  outstanding_micros: 7_000 * 1_000_000)
  end

  it '分期收了一半，状态不跟着整张台账走（整张没收清≠这期没收过）' do
    order = sales_order
    receivable_for(order, received: 1_000)
    deposit = progress(order)[:installments].first
    expect(deposit).to include(received_micros: 1_000 * 1_000_000, outstanding_micros: 2_000 * 1_000_000,
                               status: 'OVERDUE')
  end

  it '分期之和小于台账总额时，差额挂成「未排期」一行，钱不会凭空消失' do
    order = sales_order
    receivable = receivable_for(order)
    receivable.installments.find_by(seq: 2).update!(amount_micros: 5_000 * 1_000_000)
    rows = progress(order)[:installments]
    expect(rows.sum { |r| r[:amount_micros] }).to eq(10_000 * 1_000_000)
    expect(rows.last).to include(kind_label: '未排期', due_date: nil, outstanding_micros: 2_000 * 1_000_000)
  end

  it '收清了就是 100%，不会因取整显示 99%' do
    order = sales_order
    receivable = receivable_for(order, received: 10_000)
    receivable.update!(status: 'PAID')
    result = progress(order)
    expect(result[:received_percent]).to eq(100)
    expect(result[:status_label]).to eq('已收清')
  end

  it '差一分钱没收清时进度封顶 99%，不四舍五入成 100%' do
    order = sales_order
    receivable = receivable_for(order)
    receivable.update!(received_amount_micros: (10_000 * 1_000_000) - 10_000, status: 'PARTIAL')
    expect(progress(order)[:received_percent]).to eq(99)
  end

  it '外币订单原样给原币与币种，不在这里折人民币（业务员看的是签约币种）' do
    order = sales_order
    receivable_for(order, currency: 'USD', rate: 7.2)
    result = progress(order)
    expect(result[:currency]).to eq('USD')
    expect(result[:total_micros]).to eq(10_000 * 1_000_000)
  end

  it '⚠️ payload 里不得出现任何成本/应付/毛利字段——销售端与成本硬隔离' do
    order = sales_order
    receivable_for(order)
    keys = progress(order).to_json
    expect(keys).not_to match(/cost|profit|margin|payable|supplier|成本|毛利|供应商/i)
  end

  it '与催收预警算出的欠款是同一个数（同一套 FIFO 口径）' do
    order = sales_order
    receivable_for(order, received: 1_000)
    deposit = progress(order)[:installments].first
    alert = Erp::AlertScannerService.new(account, today: today).call[:overdue].first
    expect(alert[:open_micros]).to eq(deposit[:outstanding_micros])
  end
end
