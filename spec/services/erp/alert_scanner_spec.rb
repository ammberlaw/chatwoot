require 'rails_helper'

# 催收预警：只测「会不会喊错/喊漏」的硬口径。
# 催收提醒喊错比不喊更糟——业务员被误报训练几次就不看了，真逾期的那笔也一起被忽略。
RSpec.describe Erp::AlertScannerService do
  let(:account) { create(:account) }
  let(:customer) { Crm::Customer.create!(account: account, name: '客户A') }
  let(:today) { Date.new(2026, 9, 19) }

  # 一张 10000 的单：订金 3000（8/20 到期）+ 尾款 7000（9/30 到期）
  def build_receivable(received: 0)
    receivable = account.erp_receivables.create!(
      receivable_no: "AR-#{SecureRandom.hex(4)}", crm_customer: customer,
      currency: 'CNY', exchange_rate: 1,
      total_amount_micros: 10_000 * 1_000_000,
      received_amount_micros: received * 1_000_000,
      status: received.zero? ? 'UNPAID' : 'PARTIAL'
    )
    receivable.installments.create!(account: account, seq: 1, kind: 'DEPOSIT', due_basis: 'FIXED',
                                    amount_micros: 3_000 * 1_000_000, due_date: Date.new(2026, 8, 20))
    receivable.installments.create!(account: account, seq: 2, kind: 'BALANCE', due_basis: 'FIXED',
                                    amount_micros: 7_000 * 1_000_000, due_date: Date.new(2026, 9, 30))
    receivable
  end

  def scan(receivable = nil)
    receivable
    described_class.new(account, today: today).call
  end

  describe '应收分期' do
    it '一分钱没收时，过期的订金报逾期' do
      result = scan(build_receivable)
      expect(result[:overdue].size).to eq(1)
      row = result[:overdue].first
      expect(row[:kind_label]).to eq('订金')
      expect(row[:days]).to eq(30) # 8/20 → 9/19
      expect(row[:open_micros]).to eq(3_000 * 1_000_000)
    end

    it '订金已收就不再报它逾期（已收按到期日 FIFO 冲抵）' do
      result = scan(build_receivable(received: 3_000))
      expect(result[:overdue]).to be_empty
    end

    it '订金收了一半，只报剩下那一半' do
      result = scan(build_receivable(received: 1_000))
      expect(result[:overdue].size).to eq(1)
      expect(result[:overdue].first[:open_micros]).to eq(2_000 * 1_000_000)
    end

    it '尾款 11 天后到期，还没进 7 天窗口就不打扰' do
      result = scan(build_receivable(received: 3_000))
      expect(result[:due_soon]).to be_empty
    end

    it '进了 7 天窗口就报临期，days 为负数表示还没到期' do
      receivable = build_receivable(received: 3_000)
      receivable.installments.find_by(seq: 2).update!(due_date: today + 5)
      result = described_class.new(account, today: today).call
      expect(result[:due_soon].size).to eq(1)
      expect(result[:due_soon].first[:days]).to eq(-5)
      expect(result[:overdue]).to be_empty
    end

    it '收清的台账整张不再进预警' do
      receivable = build_receivable(received: 10_000)
      receivable.update!(status: 'PAID')
      expect(scan[:overdue] + scan[:due_soon]).to be_empty
    end

    it '外币按汇率折本位币给出 base_open_micros' do
      receivable = build_receivable
      receivable.update!(currency: 'USD', exchange_rate: 7.1)
      row = described_class.new(account, today: today).call[:overdue].first
      expect(row[:base_open_micros]).to eq((3_000 * 1_000_000 * 7.1).round)
    end
  end

  describe '应付账期' do
    it '到期与临期的应付都报，未到期的不报' do
      supplier = Mes::Supplier.create!(account: account, name: '供应商A', product_line: 'TABLET',
                                       supplier_no: "S#{SecureRandom.hex(3)}")
      %w[2026-09-10 2026-09-22 2026-10-30].each_with_index do |due, index|
        account.erp_payables.create!(
          payable_no: "AP-#{SecureRandom.hex(4)}-#{index}", mes_supplier: supplier,
          currency: 'CNY', exchange_rate: 1, total_amount_micros: 1_000 * 1_000_000,
          status: 'UNPAID', due_date: Date.parse(due)
        )
      end
      rows = described_class.new(account, today: today).call[:payable_due]
      # 9/10 已逾期 9 天、9/22 三天后到期都要报；10/30 太远不报
      expect(rows.size).to eq(2)
      expect(rows.first[:days]).to eq(9)
    end
  end
end
