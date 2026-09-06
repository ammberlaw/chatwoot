# 出纳日记账：收付款单落库 → 记一笔资金流水；单据作废 → 补一笔方向相反的冲销流水。
# 流水**只增不改**（§13-7），所以余额永远等于流水累计，任何时点都能对上银行对账单。
class Erp::CashLedgerService
  class Error < StandardError; end

  def initialize(account, user = nil)
    @account = account
    @user = user
  end

  # 收款单 → 流入；付款单 → 流出。改单时先撤旧流水再记新的（撤＝反向冲销，不删）。
  def sync_for(record, direction:)
    # 冲销要在「有没有资金账户」这道判断**之前**做：
    # 改单时把资金账户清空了，旧流水照样得冲掉，否则那个账户的余额一直虚高。
    reverse_for(record, reason: '单据修改')
    return if record.cash_account_id.blank?

    create_transaction(
      cash_account_id: record.cash_account_id, direction: direction,
      amount_micros: record.amount_micros, currency: record.currency, exchange_rate: record.exchange_rate,
      happened_at: record_date(record), source_type: record.class.name, source_id: record.id,
      summary: "#{record.method_label} #{document_no(record)}", counterparty: counterparty(record)
    )
  end

  # 作废/改单：把该单据已产生的流水按净额反向冲销掉。
  def reverse_for(record, reason: '单据作废')
    existing = @account.erp_cash_transactions.where(source_type: record.class.name, source_id: record.id)
    return if existing.empty?

    net = net_of(existing)
    return if net.zero?

    write_reversal(existing.first, net, record, reason)
  end

  def net_of(transactions)
    transactions.sum { |row| row.direction == Erp::CashTransaction::IN ? row.amount_micros : -row.amount_micros }
  end

  def write_reversal(reference, net, record, reason)
    create_transaction(
      cash_account_id: reference.cash_account_id,
      direction: net.positive? ? Erp::CashTransaction::OUT : Erp::CashTransaction::IN,
      amount_micros: net.abs, currency: reference.currency, exchange_rate: reference.exchange_rate,
      happened_at: Time.zone.today, source_type: record.class.name, source_id: record.id,
      summary: "冲销 #{document_no(record)}（#{reason}）", counterparty: reference.counterparty
    )
  end

  # 内部划转：转出账户一笔 OUT + 转入账户一笔 IN，一次生成，成对留痕。
  def transfer!(from_id:, to_id:, amount_micros:, happened_at:, summary: nil)
    from = @account.erp_cash_accounts.find_by(id: from_id)
    to = @account.erp_cash_accounts.find_by(id: to_id)
    raise Error, '转出/转入账户不存在' if from.blank? || to.blank?
    raise Error, '转出与转入不能是同一个账户' if from.id == to.id
    raise Error, '划转金额必须大于 0' if amount_micros.to_i <= 0
    # 暂不支持跨币种划转：两边币种不同需按汇率折算并记汇兑差额，否则按原金额记账会错账/凭证不平。
    raise Error, '暂不支持跨币种划转，请通过同币种账户或先做购汇/结汇' if from.currency != to.currency

    write_transfer_pair(from, to, amount_micros, happened_at, summary)
  end

  private

  # 一次划转 = 转出一笔 OUT + 转入一笔 IN + 一张自动凭证，同一个 source_id 串起来。
  def write_transfer_pair(from, to, amount_micros, happened_at, summary)
    # 唯一 source_id：原来用秒级时间戳，同一秒两笔划转会撞 key，reverse_for/对账按 source_id 聚合时互相串扰。
    key = SecureRandom.random_number(1 << 62)
    ActiveRecord::Base.transaction do
      write_transfer_leg(cash_account: from, direction: Erp::CashTransaction::OUT, key: key,
                         summary: summary.presence || "划转至 #{to.name}", counterparty: to.name,
                         amount_micros: amount_micros, happened_at: happened_at)
      write_transfer_leg(cash_account: to, direction: Erp::CashTransaction::IN, key: key,
                         summary: summary.presence || "由 #{from.name} 划入", counterparty: from.name,
                         amount_micros: amount_micros, happened_at: happened_at)
      Erp::AutoVoucherService.new(@account).for_transfer(from, to, amount_micros, happened_at, key)
    end
    [from.reload, to.reload]
  end

  # leg: { cash_account:, direction:, key:, summary:, counterparty:, amount_micros:, happened_at: }
  def write_transfer_leg(leg)
    create_transaction(cash_account_id: leg[:cash_account].id, direction: leg[:direction],
                       amount_micros: leg[:amount_micros], currency: leg[:cash_account].currency,
                       exchange_rate: 1, happened_at: leg[:happened_at],
                       source_type: 'Erp::CashTransfer', source_id: leg[:key],
                       summary: leg[:summary], counterparty: leg[:counterparty])
  end

  def create_transaction(attrs)
    @account.erp_cash_transactions.create!(attrs.merge(created_by_id: @user&.id))
  end

  def record_date(record)
    record.respond_to?(:received_at) ? record.received_at : record.paid_at
  end

  def document_no(record)
    record.respond_to?(:receipt_no) ? record.receipt_no : record.payment_no
  end

  def counterparty(record)
    record.respond_to?(:crm_customer) ? record.crm_customer&.name : record.mes_supplier&.name
  end
end
