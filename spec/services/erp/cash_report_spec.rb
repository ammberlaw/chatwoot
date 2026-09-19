# frozen_string_literal: true

require 'rails_helper'

# 资金报表：财务月末对账用的表，三条硬口径错一条就对不上账。
RSpec.describe Erp::CashReportService do
  let(:account) { create(:account) }
  let(:period) { '2026-09' }

  def cash_account(name:, currency: 'CNY', opening: 0, opening_base: nil)
    account.erp_cash_accounts.create!(
      name: name, kind: 'BANK', currency: currency,
      opening_balance_micros: opening * 1_000_000,
      opening_base_amount_micros: opening_base && opening_base * 1_000_000
    )
  end

  def txn(cash_acc, direction:, amount:, on:, rate: 1)
    account.erp_cash_transactions.create!(
      cash_account: cash_acc, direction: direction, amount_micros: amount * 1_000_000,
      currency: cash_acc.currency, exchange_rate: rate, happened_at: on
    )
  end

  def report = described_class.new(account).call(period: period)
  def row_for(name) = report[:rows].find { |row| row[:name] == name }

  it '期末 = 期初 + 收 − 支（原币恒等式）' do
    acc = cash_account(name: '中行', opening: 10_000)
    txn(acc, direction: 'IN', amount: 3_000, on: Date.new(2026, 9, 5))
    txn(acc, direction: 'OUT', amount: 1_200, on: Date.new(2026, 9, 20))

    row = row_for('中行')
    expect(row[:opening_micros]).to eq(10_000 * 1_000_000)
    expect(row[:in_micros]).to eq(3_000 * 1_000_000)
    expect(row[:out_micros]).to eq(1_200 * 1_000_000)
    expect(row[:closing_micros]).to eq(11_800 * 1_000_000)
  end

  it '期初含期间开始日之前的全部流水，不只是账户上那个期初数' do
    acc = cash_account(name: '中行', opening: 10_000)
    txn(acc, direction: 'IN', amount: 5_000, on: Date.new(2026, 8, 31)) # 上月
    expect(row_for('中行')[:opening_micros]).to eq(15_000 * 1_000_000)
    expect(row_for('中行')[:in_micros]).to be_zero # 上月的不算本期收
  end

  it '期间外的流水一概不进本期收支（边界日含当天）' do
    acc = cash_account(name: '中行')
    txn(acc, direction: 'IN', amount: 100, on: Date.new(2026, 9, 1))
    txn(acc, direction: 'IN', amount: 200, on: Date.new(2026, 9, 30))
    txn(acc, direction: 'IN', amount: 400, on: Date.new(2026, 10, 1))
    expect(row_for('中行')[:in_micros]).to eq(300 * 1_000_000)
  end

  it '折 CNY 走账面本位币：外币流水按各自发生日汇率折，不按期末汇率重估' do
    acc = cash_account(name: '招行美元户', currency: 'USD', opening: 1_000, opening_base: 7_000)
    txn(acc, direction: 'IN', amount: 100, on: Date.new(2026, 9, 10), rate: 7.2)
    txn(acc, direction: 'IN', amount: 100, on: Date.new(2026, 9, 20), rate: 7.0)

    row = row_for('招行美元户')
    expect(row[:closing_micros]).to eq(1_200 * 1_000_000)      # 原币
    expect(row[:in_base_micros]).to eq(1_420 * 1_000_000)      # 720 + 700，不是 200×某一个汇率
    expect(row[:closing_base_micros]).to eq(8_420 * 1_000_000) # 7000 + 1420
  end

  it '⚠️ 外币账户没填期初本位币时本位币列留空，绝不按 1:1 当人民币加' do
    cash_account(name: '欧元户', currency: 'EUR', opening: 5_000) # 没填 opening_base
    cash_account(name: '中行', opening: 10_000)

    result = report
    eur = result[:rows].find { |row| row[:name] == '欧元户' }
    expect(eur[:base_unknown]).to be(true)
    expect(eur[:opening_base_micros]).to be_nil
    expect(eur[:closing_base_micros]).to be_nil
    # 合计里只有人民币那 10000，欧元的 5000 没被当成 5000 元加进来
    expect(result[:totals][:closing_base_micros]).to eq(10_000 * 1_000_000)
    expect(result[:missing_base_accounts]).to eq(['欧元户'])
  end

  it 'CNY 账户的期初本位币不用填，就是它自己' do
    cash_account(name: '备用金', opening: 800)
    row = row_for('备用金')
    expect(row[:base_unknown]).to be(false)
    expect(row[:opening_base_micros]).to eq(800 * 1_000_000)
  end

  it '按币种小计用原币，不跨币种相加' do
    cash_account(name: '中行', opening: 10_000)
    cash_account(name: '备用金', opening: 800)
    cash_account(name: '美元户', currency: 'USD', opening: 1_000, opening_base: 7_000)

    groups = report[:by_currency]
    expect(groups.map { |row| row[:currency] }).to eq(%w[CNY USD]) # 本位币排最前
    expect(groups.first[:closing_micros]).to eq(10_800 * 1_000_000)
    expect(groups.second[:closing_micros]).to eq(1_000 * 1_000_000)
  end

  it '没有任何流水的月份也能出表（全零不报错）' do
    cash_account(name: '中行', opening: 10_000)
    result = described_class.new(account).call(period: '2026-01')
    expect(result[:rows].first[:closing_micros]).to eq(10_000 * 1_000_000)
    expect(result[:totals][:in_base_micros]).to be_zero
  end

  it '期间格式非法时明确报错，不是静默出一张空表' do
    expect { described_class.new(account).call(period: '2026/09') }.to raise_error(ArgumentError, /YYYY-MM/)
  end
end
