# frozen_string_literal: true

require 'rails_helper'

# 费用报销打款（ERP_SYSTEM §3.35）。员工在 OA 报销、财务在 ERP 付钱，
# 一次打款要同时落三件事：出纳流水、待过账凭证、挂订单的成本行。
#
# 为什么必须测：这三件事任何一件没跟上都是**静默**的——
# 钱照付、页面照样显示「已打款」，只是总账少一张凭证、或者资金余额对不上银行，
# 要等月末对账才发现，那时已经隔了几十笔。
RSpec.describe Erp::ExpensePayoutService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:applicant) { create(:user, account: account) }
  let(:customer) { create(:crm_customer, account: account) }
  let(:service) { described_class.new(account) }
  let(:today) { Time.zone.today }

  let(:bank) { account.erp_ledger_accounts.find_by(code: '100201') }
  let(:travel) { account.erp_ledger_accounts.find_by(code: '660104') }
  let(:cash_account) do
    account.erp_cash_accounts.create!(name: '基本户', kind: 'BANK', currency: 'CNY',
                                      ledger_account_id: bank.id, opening_balance_micros: 0)
  end

  before { Erp::ChartOfAccountsService.ensure_standard!(account) }

  # 标了 erp_expense 的报销模板：金额字段是 type=amount 的第一个字段（与备用金联动同口径）。
  def template(erp_expense: true, name: '费用报销')
    account.oa_approval_templates.create!(
      name: name, erp_expense: erp_expense, flow: [],
      form_fields: [
        { 'key' => 'category', 'type' => 'select', 'label' => '费用类型' },
        { 'key' => 'amount', 'type' => 'amount', 'label' => '报销金额' },
        { 'key' => 'note', 'type' => 'textarea', 'label' => '费用说明' }
      ]
    )
  end

  def approval(tpl = template, category: '差旅', amount: '1280.50', status: 'approved')
    account.oa_approval_requests.create!(
      template: tpl, applicant_id: applicant.id, title: "#{applicant.name}的费用报销",
      form_data: { 'category' => category, 'amount' => amount, 'note' => '广交会机票' },
      status: status, current_position: 0, submitted_at: Time.current
    )
  end

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

  def pay!(request, amount: 1280.50, order: nil, paid_at: nil)
    service.pay!({
                   oa_approval_request_id: request.id,
                   amount_micros: (amount * 1_000_000).round,
                   expense_ledger_account_id: travel.id,
                   cash_account_id: cash_account.id,
                   crm_sales_order_id: order&.id,
                   cost_type: order ? 'EXPENSE' : nil,
                   paid_at: paid_at || today
                 }, actor: user)
  end

  def voucher_of(payout)
    account.erp_vouchers.where(source_type: 'Erp::ExpensePayout', source_id: payout.id)
           .where.not(status: Erp::Voucher::VOID).last
  end

  def transactions_of(payout)
    account.erp_cash_transactions.where(source_type: 'Erp::ExpensePayout', source_id: payout.id)
  end

  def cost_of(payout)
    account.erp_order_costs.find_by(source_type: 'Erp::ExpensePayout', source_id: payout.id)
  end

  describe '待打款筛选' do
    it '只收「标了财务联动的模板 + 审批通过」的单' do
      wanted = approval
      approval(template, status: 'pending')                        # 还没批完
      approval(template(erp_expense: false, name: '请假申请'))       # 不是报销模板

      expect(service.pending_requests.map(&:id)).to eq([wanted.id])
    end

    it '打过款的不再出现，作废后又回到待打款' do
      request = approval
      payout = pay!(request)
      expect(service.pending_requests).to be_empty

      service.void!(payout, actor: user)
      expect(described_class.new(account).pending_requests.map(&:id)).to eq([request.id])
    end

    it '金额取表单里 type=amount 的字段，费用类型按映射带出科目' do
      expect(described_class.request_amount_micros(approval)).to eq(1_280_500_000)
      expect(service.default_expense_account('差旅').code).to eq('660104')
      expect(service.default_expense_account('招待').code).to eq('660103')
      # 科目表没单列交通费，交通复用差旅费
      expect(service.default_expense_account('交通').code).to eq('660104')
      # 没见过的类型落兜底科目，不能返回 nil 让财务面对空下拉
      expect(service.default_expense_account('外星费用').code).to eq('660199')
    end

    it '金额字段为空或非数字的单不给出金额（页面据此禁用打款按钮）' do
      expect(described_class.request_amount_micros(approval(template, amount: ''))).to be_nil
      expect(described_class.request_amount_micros(approval(template, amount: '待定'))).to be_nil
      expect(described_class.request_amount_micros(approval(template, amount: '0'))).to be_nil
    end
  end

  describe '打款的三个副作用' do
    it '出纳日记账记一笔流出，对方单位是报销人' do
      payout = pay!(approval)
      rows = transactions_of(payout)

      expect(rows.count).to eq(1)
      expect(rows.first.direction).to eq(Erp::CashTransaction::OUT)
      expect(rows.first.amount_micros).to eq(1_280_500_000)
      expect(rows.first.counterparty).to eq(applicant.name)
    end

    it '资金账户余额按实付减少' do
      expect { pay!(approval) }
        .to change { cash_account.reload.balance_micros }.by(-1_280_500_000)
    end

    it '生成待过账凭证：借 费用科目 / 贷 货币资金，借贷相等' do
      voucher = voucher_of(pay!(approval))

      expect(voucher.status).to eq(Erp::Voucher::DRAFT)
      expect(voucher.total_debit_micros).to eq(voucher.total_credit_micros)
      debit = voucher.lines.find { |l| l.direction == 'DEBIT' }
      credit = voucher.lines.find { |l| l.direction == 'CREDIT' }
      expect(debit.ledger_account_id).to eq(travel.id)
      expect(credit.ledger_account_id).to eq(bank.id)
      expect(debit.amount_micros).to eq(1_280_500_000)
    end

    it '挂了订单才建成本行，不挂就没有' do
      order = sales_order
      expect(cost_of(pay!(approval, order: order)).crm_sales_order_id).to eq(order.id)
      expect(cost_of(pay!(approval))).to be_nil
    end

    it '成本行金额与打款额一致、类型是报销费用' do
      cost = cost_of(pay!(approval, amount: 860.50, order: sales_order))

      expect(cost.amount_micros).to eq(860_500_000)
      expect(cost.cost_type).to eq('EXPENSE')
    end

    it '通知报销人已打款' do
      expect { pay!(approval) }
        .to change { account.mes_notifications.where(kind: 'erp_expense_paid', recipient_id: applicant.id).count }
        .by(1)
    end

    it '财务核减后，流水/凭证/成本三处都按实付走，不是申请额' do
      # 申请 1280.50，发票不全只报 900
      payout = pay!(approval, amount: 900, order: sales_order)

      expect(payout.amount_micros).to eq(900_000_000)
      expect(transactions_of(payout).sum(:amount_micros)).to eq(900_000_000)
      expect(voucher_of(payout).total_debit_micros).to eq(900_000_000)
      expect(cost_of(payout).amount_micros).to eq(900_000_000)
    end
  end

  describe '改单' do
    it '改金额后流水净额、凭证、成本行一起跟着变' do
      order = sales_order
      payout = pay!(approval, amount: 1000, order: order)
      service.update_payout!(payout, { amount_micros: 600_000_000 }, actor: user)

      # 流水是「只增不改」：旧的冲销 + 新的记入，净额＝新金额
      net = transactions_of(payout).sum { |t| t.direction == Erp::CashTransaction::OUT ? t.amount_micros : -t.amount_micros }
      expect(net).to eq(600_000_000)
      expect(cash_account.reload.balance_micros).to eq(-600_000_000)
      expect(voucher_of(payout).total_debit_micros).to eq(600_000_000)
      expect(cost_of(payout).amount_micros).to eq(600_000_000)
    end

    it '取消挂订单后成本行删掉，不能留在毛利表里' do
      payout = pay!(approval, order: sales_order)
      service.update_payout!(payout, { crm_sales_order_id: nil }, actor: user)

      expect(cost_of(payout)).to be_nil
    end

    it '不许把打款单改挂到另一张审批单上' do
      payout = pay!(approval)
      other = approval

      service.update_payout!(payout, { oa_approval_request_id: other.id, amount_micros: 500_000_000 }, actor: user)
      expect(payout.reload.amount_micros).to eq(500_000_000)
      expect(payout.oa_approval_request_id).not_to eq(other.id)
    end
  end

  describe '作废' do
    it '资金流水冲平、余额还原' do
      payout = pay!(approval)
      expect { service.void!(payout, actor: user) }
        .to change { cash_account.reload.balance_micros }.from(-1_280_500_000).to(0)
    end

    it '成本行删除，凭证作废' do
      payout = pay!(approval, order: sales_order)
      service.void!(payout, actor: user)

      expect(cost_of(payout)).to be_nil
      expect(account.erp_vouchers.where(source_type: 'Erp::ExpensePayout', source_id: payout.id).last.status)
        .to eq(Erp::Voucher::VOID)
    end

    it '凭证已过账的不动它，回凭证号让财务去红冲' do
      payout = pay!(approval)
      Erp::VoucherPostingService.new(voucher_of(payout), user).post!

      posted_no = service.void!(payout, actor: user)
      expect(posted_no).to be_present
      expect(account.erp_vouchers.find_by(voucher_no: posted_no).status).to eq(Erp::Voucher::POSTED)
    end
  end

  describe '不变量' do
    it '同一张审批单不能打两次款' do
      request = approval
      pay!(request)

      expect { pay!(request) }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it '打过款的审批单删不掉——删了流水和凭证会变成查不到来源的无主记录' do
      request = approval
      pay!(request)

      expect(request.destroy).to be_falsey
      expect(account.oa_approval_requests.exists?(request.id)).to be(true)
    end

    it '删审批模板会被连带拦下，不会级联清掉打款单' do
      tpl = template
      pay!(approval(tpl))

      begin
        tpl.destroy
      rescue ActiveRecord::InvalidForeignKey
        # Rails 层的 restrict_with_error 没拦住时，DB 外键兜底——两种都算拦下
      end

      expect(account.oa_approval_templates.exists?(tpl.id)).to be(true)
      expect(account.erp_expense_payouts.count).to eq(1)
    end
  end
end
