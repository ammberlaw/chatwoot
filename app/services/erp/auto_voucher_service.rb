# 自动凭证：收款单 / 付款单 / 内部划转落库后自动生成**待过账**凭证进队列，财务审一眼过账。
#
# 设计取舍：
# - 只生成 DRAFT，绝不自动过账——过账是会计确认动作，必须有人点（§8.3）。
# - 单据改动就整张重生成：原来那张 DRAFT 直接换掉；已过账的不动，提示财务红冲（§13-5 POSTED 不可改）。
# - 科目按 account_type 找（BANK/CASH/RECEIVABLE/PAYABLE/EXPENSE），不靠中文名匹配；
#   规则 config 里可覆盖具体科目 id。
class Erp::AutoVoucherService
  class Error < StandardError; end

  FEE_ACCOUNT_CODE = '660302'.freeze # 财务费用-手续费

  def initialize(account)
    @account = account
  end

  # 收款：借 货币资金(净额) + 借 手续费 / 贷 应收账款〔客户维度〕
  def for_receipt(receipt)
    return if skip?(Erp::AutoVoucherRule::RECEIPT, receipt)

    cash = cash_account_for(receipt)
    receivable = party_account(receipt, :receivable)
    return if cash.blank? || receivable.blank?

    gross = receipt.amount_micros + receipt.bank_charge_micros
    # 外币下各借方行分别 round(原币×汇率)，贷方应收 base 必须用两借方 base 之和倒挤，
    # 否则 round(a)+round(b)≠round(a+b) 差 1 分致凭证不平过不了账。
    rate = receipt.exchange_rate.to_d
    cash_base = Erp::VoucherLine.round_to_cent(receipt.amount_micros * rate)
    fee_base = receipt.bank_charge_micros.positive? ? Erp::VoucherLine.round_to_cent(receipt.bank_charge_micros * rate) : 0
    lines = [line(account: cash, direction: 'DEBIT', amount_micros: receipt.amount_micros, record: receipt,
                  summary: '收到货款')]
    if receipt.bank_charge_micros.positive?
      lines << line(account: fee_account, direction: 'DEBIT', amount_micros: receipt.bank_charge_micros,
                    record: receipt, summary: '银行手续费')
    end
    lines << line(account: receivable, direction: 'CREDIT', amount_micros: gross, record: receipt,
                  summary: '冲减应收', dimension: { crm_customer_id: receipt.crm_customer_id })
                 .merge(base_amount_micros: cash_base + fee_base, explicit_base: true)

    build_voucher(receipt, "收款 #{receipt.receipt_no} · #{receipt.crm_customer&.name}", receipt.received_at, lines)
  end

  # 付款：借 应付账款〔供应商维度〕 / 贷 货币资金 + 手续费另行借记
  def for_payment(payment)
    return if skip?(Erp::AutoVoucherRule::PAYMENT, payment)

    cash = cash_account_for(payment)
    payable = party_account(payment, :payable)
    return if cash.blank? || payable.blank?

    rate = payment.exchange_rate.to_d
    payable_base = Erp::VoucherLine.round_to_cent(payment.amount_micros * rate)
    fee_base = payment.bank_charge_micros.positive? ? Erp::VoucherLine.round_to_cent(payment.bank_charge_micros * rate) : 0
    lines = [line(account: payable, direction: 'DEBIT', amount_micros: payment.amount_micros, record: payment,
                  summary: '冲减应付', dimension: { mes_supplier_id: payment.mes_supplier_id })]
    if payment.bank_charge_micros.positive?
      lines << line(account: fee_account, direction: 'DEBIT', amount_micros: payment.bank_charge_micros,
                    record: payment, summary: '银行手续费')
    end
    total_out = payment.amount_micros + payment.bank_charge_micros
    # 贷方货币资金 base 用两借方 base 之和倒挤，保证外币下借贷严格相等(见 for_receipt)。
    lines << line(account: cash, direction: 'CREDIT', amount_micros: total_out, record: payment, summary: '付出款项')
              .merge(base_amount_micros: payable_base + fee_base, explicit_base: true)

    build_voucher(payment, "付款 #{payment.payment_no} · #{payment.mes_supplier&.name}", payment.paid_at, lines)
  end

  # 内部划转：借 转入账户 / 贷 转出账户（跨币种的汇兑差额在 §7.2 落地后再补）
  def for_transfer(from_account, to_account, amount_micros, happened_at, source_key)
    rule = rule_for(Erp::AutoVoucherRule::CASH_TRANSFER)
    return if rule.blank? || !rule.is_active?
    return if from_account.ledger_account.blank? || to_account.ledger_account.blank?

    lines = [
      { ledger_account_id: to_account.ledger_account_id, direction: 'DEBIT', amount_micros: amount_micros,
        summary: "转入 #{to_account.name}", currency: to_account.currency, exchange_rate: 1 },
      { ledger_account_id: from_account.ledger_account_id, direction: 'CREDIT', amount_micros: amount_micros,
        summary: "转出 #{from_account.name}", currency: from_account.currency, exchange_rate: 1 }
    ]
    create_voucher!(source_type: 'Erp::CashTransfer', source_id: source_key, date: happened_at,
                    summary: "内部划转 #{from_account.name} → #{to_account.name}", lines: lines)
  end

  # 单据作废：DRAFT 凭证直接作废；已过账的留给财务红冲（返回该凭证号供页面提示）。
  def void_for(record)
    voucher = existing_voucher(record)
    return nil if voucher.blank?

    if voucher.status == Erp::Voucher::DRAFT
      voucher.update!(status: Erp::Voucher::VOID)
      nil
    else
      voucher.voucher_no
    end
  end

  private

  def rule_for(event_key)
    Erp::AutoVoucherRule.ensure_defaults!(@account) if @account.erp_auto_voucher_rules.empty?
    @account.erp_auto_voucher_rules.find_by(event_key: event_key)
  end

  def skip?(event_key, record)
    rule = rule_for(event_key)
    rule.blank? || !rule.is_active? || record.cash_account_id.blank?
  end

  def cash_account_for(record)
    @account.erp_cash_accounts.find_by(id: record.cash_account_id)&.ledger_account
  end

  PARTY_SPECS = {
    receivable: { event: Erp::AutoVoucherRule::RECEIPT, key: 'receivable_account_id', type: 'RECEIVABLE' },
    payable: { event: Erp::AutoVoucherRule::PAYMENT, key: 'payable_account_id', type: 'PAYABLE' }
  }.freeze

  # 往来科目按币种挑：外币单据进外币应收/应付科目（币种必须与科目一致，否则分录行校验会拦）。
  def party_account(record, kind)
    spec = PARTY_SPECS.fetch(kind)
    override = rule_for(spec[:event])&.config&.dig(spec[:key])
    return @account.erp_ledger_accounts.find_by(id: override) if override.present?

    scope = @account.erp_ledger_accounts.active.leaves.where(account_type: spec[:type])
    scope.find_by(currency: record.currency) || scope.find_by(currency: nil)
  end

  def fee_account
    @fee_account ||= @account.erp_ledger_accounts.find_by(code: FEE_ACCOUNT_CODE)
  end

  # dimension: { crm_customer_id: } 或 { mes_supplier_id: }，往来科目要求必填维度。
  # spec: { account:, direction:, amount_micros:, record:, summary:, dimension? }
  def line(spec)
    {
      ledger_account_id: spec[:account].id, direction: spec[:direction], amount_micros: spec[:amount_micros],
      summary: spec[:summary], currency: spec[:record].currency, exchange_rate: spec[:record].exchange_rate
    }.merge(spec[:dimension] || {})
  end

  def build_voucher(record, summary, date, lines)
    create_voucher!(source_type: record.class.name, source_id: record.id, date: date, summary: summary, lines: lines)
  end

  # 已记账的自动凭证不会被重写。原来是**静默**返回旧凭证——
  # 于是「改了单据金额 → 台账和资金流水都跟着变、凭证还停在旧金额」，
  # 总账与台账就此不平，而且没有任何人被告知。
  # 现在：分录没变就照旧返回（改备注之类不该报错），一旦金额/科目/维度变了就拦下来。
  def guard_posted!(previous, lines)
    return previous if signature(previous.lines) == signature(lines)

    raise Error, "本单已生成凭证 #{previous.voucher_no} 并已记账，改动不会自动同步到凭证。" \
                 '请先红冲该凭证，再修改单据。'
  end

  SIGNATURE_KEYS = %i[ledger_account_id direction amount_micros crm_customer_id mes_supplier_id].freeze

  def signature(lines)
    lines.map { |line| SIGNATURE_KEYS.map { |key| line.is_a?(Hash) ? line[key] : line.public_send(key) } }.sort_by(&:to_s)
  end

  def existing_voucher(record)
    @account.erp_vouchers.where(source_type: record.class.name, source_id: record.id)
            .where.not(status: Erp::Voucher::VOID).order(:id).last
  end

  # 重生成：旧的 DRAFT 换掉；已过账的保留（财务得走红冲），此时不再生成新的，避免重复入账。
  def create_voucher!(source_type:, source_id:, date:, summary:, lines:)
    # 按来源单据 advisory 锁：串行化「查旧草稿→删→建新」，杜绝并发/重试给同一单据生成两张草稿自动凭证
    # （+ DB 部分唯一索引 uniq_erp_voucher_draft_source 兜底）。
    Erp::AccountLock.with_account_lock(@account.id, "autovoucher:#{source_type}:#{source_id}") do
      previous = @account.erp_vouchers.where(source_type: source_type, source_id: source_id)
                         .where.not(status: Erp::Voucher::VOID).order(:id).last
      if previous&.status == Erp::Voucher::POSTED
        guard_posted!(previous, lines)
      else
        previous&.destroy
        voucher = @account.erp_vouchers.create!(
          voucher_date: date, summary: summary, status: Erp::Voucher::DRAFT,
          source_type: source_type, source_id: source_id,
          lines_attributes: lines.each_with_index.map { |row, index| row.merge(position: index) }
        )
        voucher.refresh_totals!
        voucher
      end
    end
  end
end
