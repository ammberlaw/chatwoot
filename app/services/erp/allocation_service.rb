# 核销：把收/付款单拆到应收/应付台账上。**唯一允许改台账已收/已付金额的地方**。
#
# 守恒规则（ERP_SPEC §13-3）：
#   Σ核销 ≤ 单据金额，且每笔核销 ≤ 该台账未收/未付余额；
#   台账 received/paid 与 status 全部由本服务重算，不接受外部直接赋值。
# 作废（§13-4）：已核销的收付款单不可改删，只能作废——作废时回滚全部核销与台账余额。
class Erp::AllocationService
  class Error < StandardError; end

  # kind: :receipt（收款→应收）/ :payment（付款→应付）
  def initialize(record, kind)
    @record = record
    @kind = kind
  end

  # allocations: [{ ledger_id:, amount_micros: }]，整单覆盖式重设（先清后建，保证幂等）。
  def apply!(allocations)
    rows = normalize(allocations)
    ActiveRecord::Base.transaction do
      touched = @record.allocations.map(&ledger_key).uniq
      # 先对涉及的台账行加 FOR UPDATE 行锁：串行化并发核销同一台账，杜绝两单各读旧余额都通过校验→超额核销。
      ledger_scope.lock.where(id: (touched + rows.map { |r| r[:ledger_id] }).uniq).to_a
      @record.allocations.destroy_all
      # 删核销行只是删了明细，台账的已收/已付是**缓存字段**，得先刷一遍把本单占用的额度还回去，
      # 再去校验新的核销额。不刷的话 outstanding_excluding_self 读到的还是含本单的旧值，
      # 改单时（哪怕金额没变）必报「核销金额超出未结余额」。
      touched.each { |id| refresh_ledger!(id) }
      rows.each { |row| create_allocation!(row) }
      validate_record_total!
      (touched + rows.map { |row| row[:ledger_id] }).uniq.each { |id| refresh_ledger!(id) }
    end
    @record.reload
  end

  # 作废：回滚核销与台账余额，单据留痕。
  def void!
    raise Error, '该单据已作废' unless @record.voidable?

    ActiveRecord::Base.transaction do
      touched = @record.allocations.map(&ledger_key).uniq
      ledger_scope.lock.where(id: touched).to_a # 行锁台账,与并发核销/作废串行
      @record.allocations.destroy_all
      @record.update!(status: void_status)
      touched.each { |id| refresh_ledger!(id) }
    end
    @record
  end

  private

  def receipt?
    @kind == :receipt
  end

  def ledger_key
    receipt? ? :receivable_id : :payable_id
  end

  def void_status
    receipt? ? Erp::ReceiptRecord::VOID : Erp::PaymentRecord::VOID
  end

  def ledger_scope
    receipt? ? @record.account.erp_receivables : @record.account.erp_payables
  end

  def normalize(allocations)
    Array(allocations).filter_map do |row|
      amount = row[:amount_micros].to_i
      next if amount <= 0

      { ledger_id: row[:ledger_id].to_i, amount_micros: amount }
    end
  end

  def create_allocation!(row)
    ledger = ledger_scope.find_by(id: row[:ledger_id])
    raise Error, '要核销的台账不存在' if ledger.blank?

    # 核销金额是**原币**直接记进台账的已收/已付，所以两边币种必须一致。
    # 不卡的话，1000 美元的收款单核到人民币台账，就当成 1000 人民币记进去了。
    if ledger.currency != @record.currency
      raise Error, "单据是 #{@record.currency}、台账「#{ledger_no(ledger)}」是 #{ledger.currency}，" \
                   '币种不一致不能核销；请先按同币种建账'
    end

    # 往来对象必须一致：收款单客户==应收台账客户 / 付款单供应商==应付台账供应商，防把 A 的钱核到 B 的账。
    party_ok = receipt? ? ledger.crm_customer_id == @record.crm_customer_id : ledger.mes_supplier_id == @record.mes_supplier_id
    raise Error, "单据与台账「#{ledger_no(ledger)}」的#{receipt? ? '客户' : '供应商'}不一致，不能核销" unless party_ok

    available = outstanding_excluding_self(ledger)
    raise Error, "核销金额超出「#{ledger_no(ledger)}」的未结余额（可核销 #{fmt(available)}）" if row[:amount_micros] > available

    @record.allocations.create!(
      :account_id => @record.account_id, ledger_key => ledger.id, :amount_micros => row[:amount_micros]
    )
  end

  # 本单原有的核销已在 apply! 里清掉，这里算的是「除本单外」的占用，避免改单时误判超额。
  def outstanding_excluding_self(ledger)
    ledger.reload
    paid = receipt? ? ledger.received_amount_micros : ledger.paid_amount_micros
    ledger.total_amount_micros - paid
  end

  # 上限是**毛额**（到账净额＋银行手续费）：客户还 1000、银行扣 3、到账 997，
  # 自动凭证按 1000 贷应收，核销也必须能核到 1000——按净额 997 卡的话，
  # 每张带手续费的收款单都会在台账上留一笔等于手续费的假「未收」，总账与台账永远差手续费累计额。
  def validate_record_total!
    total = @record.allocations.sum(:amount_micros)
    gross = @record.amount_micros + @record.bank_charge_micros.to_i
    return if total <= gross

    raise Error, "核销合计 #{fmt(total)} 超出单据金额 #{fmt(gross)}（含手续费）"
  end

  # 台账余额 = 该台账上所有核销之和；状态由余额派生。
  def refresh_ledger!(ledger_id)
    ledger = ledger_scope.find_by(id: ledger_id)
    return if ledger.blank?

    total = allocation_scope(ledger).sum(:amount_micros)
    column = receipt? ? :received_amount_micros : :paid_amount_micros
    ledger.assign_attributes(column => total)
    ledger.status = ledger.derived_status
    ledger.save!
    sync_order_completion(ledger)
  end

  # 收清了就把销售订单推到完结；收款单作废/改小又退回已出货（对称，否则作废后订单还挂着"已完结"）。
  # 应付侧没有这个联动——采购付款不决定销售订单的状态。
  def sync_order_completion(ledger)
    return unless receipt?

    Erp::OrderCompletionService.new(@record.account).sync_for_receivable(ledger)
  end

  # 只算正常单据的核销：作废单据的核销行已删除，这里再按状态挡一层。
  def allocation_scope(ledger)
    if receipt?
      Erp::ReceiptAllocation.joins(:receipt_record)
                            .where(receivable_id: ledger.id, erp_receipt_records: { status: Erp::ReceiptRecord::NORMAL })
    else
      Erp::PaymentAllocation.joins(:payment_record)
                            .where(payable_id: ledger.id, erp_payment_records: { status: Erp::PaymentRecord::NORMAL })
    end
  end

  def ledger_no(ledger)
    receipt? ? ledger.receivable_no : ledger.payable_no
  end

  def fmt(micros)
    format('%.2f', micros.to_i / 1_000_000.0)
  end
end
