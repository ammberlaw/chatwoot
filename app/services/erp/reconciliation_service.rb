# 两账对平（ERP_SPEC §9.4）：业务台账 vs 会计总账，每月结账前必须零差异。
#
# 对三组：
#   应收台账未收合计  vs  应收账款科目余额
#   应付台账未付合计  vs  应付账款科目余额
#   资金账户余额合计  vs  货币资金科目余额
# 有差异通常是「单据没生成凭证」或「凭证记错科目」，页面直接把差额摆出来。
class Erp::ReconciliationService
  GROUPS = [
    { key: 'receivable', label: '应收', account_type: 'RECEIVABLE' },
    { key: 'payable', label: '应付', account_type: 'PAYABLE' },
    { key: 'cash', label: '资金', account_type: %w[CASH BANK] }
  ].freeze

  def initialize(account)
    @account = account
  end

  def call(as_of: Time.zone.today)
    balances = Erp::LedgerQueryService.new(@account).balances(from: Erp::FinancialReportService::EPOCH, to: as_of)
    GROUPS.map { |group| row_for(group, balances) }
  end

  private

  def row_for(group, balances)
    ledger = ledger_balance(group[:account_type], balances)
    business = business_balance(group[:key])
    diff = business - ledger
    { key: group[:key], label: group[:label], business_micros: business, ledger_micros: ledger,
      diff_micros: diff, matched: business == ledger, note: note_for(group[:key]),
      breakdown: group[:key] == 'receivable' ? receivable_breakdown(diff) : [] }
  end

  # 应收差额的构成拆解。
  #
  # 台账和总账天生不同步：台账在**订单确认**时建，应收账款在**发货**确认收入时才借记。
  # 所以「已建账未发货」是一笔结构性差额，不是错账；只给财务一个总差额数字，
  # 他看不出哪部分是时点差、哪部分是真出了问题。这里把能解释的两段点名，
  # 剩下的归「其他」——其他不为零才是要查的。
  def receivable_breakdown(diff)
    pending = pending_revenue_micros
    unbooked = unbuilt_ledger_micros
    [
      { key: 'pending_revenue', label: '已建账·尚未发货（时点差）', amount_micros: pending,
        note: '订单确认即建台账，发货才确认收入借记应收——发货后自动消除' },
      { key: 'unbuilt_ledger', label: '已发货·台账未建', amount_micros: -unbooked,
        note: '收入凭证已借记应收，但这张订单没建台账——去「待建账」补建' },
      { key: 'other', label: '其他（需排查）', amount_micros: diff - pending + unbooked,
        note: '不为零说明有凭证记错科目或手工动过应收账款' }
    ]
  end

  # 已建台账、但收入凭证还没出的未收额（本位币台账）。
  def pending_revenue_micros
    scope = @account.erp_receivables.where(currency: 'CNY').where.not(crm_sales_order_id: nil)
                    .where.not(crm_sales_order_id: revenue_booked_order_ids)
    scope.sum(:total_amount_micros) - scope.sum(:received_amount_micros)
    # 没挂订单的手工台账不算在这一段里：它没有「等发货」这回事，差了就该进「其他」。
  end

  # 收入凭证已记账、但没建台账的订单金额（本位币订单）。
  def unbuilt_ledger_micros
    built = @account.erp_receivables.where.not(crm_sales_order_id: nil).select(:crm_sales_order_id)
    @account.crm_sales_orders.where(id: revenue_booked_order_ids).where.not(id: built)
            .where(order_currency: [nil, 'CNY'])
            .sum(&:receivable_amount_micros)
  end

  # 出过收入凭证（已记账）的销售订单。成本凭证的 source_type 带 ::Cost 后缀，天然排除。
  def revenue_booked_order_ids
    @revenue_booked_order_ids ||= begin
      shipment_ids = @account.erp_vouchers
                             .where(source_type: 'Mes::Shipment', status: Erp::Voucher::POSTED)
                             .pluck(:source_id)
      shipment_ids.empty? ? [] : @account.mes_shipments.where(id: shipment_ids).pluck(:crm_sales_order_id).compact.uniq
    end
  end

  # 外币的本位币余额只能由凭证（按录入时汇率折算）决定，与台账/账户原币余额不可比，
  # 所以三组都只对本位币，外币的量单独提示、按外币另行核对——没有提示的排除项等于「假绿灯」。
  def note_for(key)
    count = case key
            when 'cash' then @account.erp_cash_accounts.active.where.not(currency: 'CNY').count
            when 'receivable' then @account.erp_receivables.where.not(currency: 'CNY').count
            else @account.erp_payables.where.not(currency: 'CNY').count
            end
    return nil if count.zero?

    unit = key == 'cash' ? '个外币账户' : '条外币台账'
    "另有 #{count} #{unit}未纳入本位币对平，请按外币单独核对"
  end

  # 总账侧取本位币科目：currency 为空＝本位币；财务把科目显式标成 CNY 也算——
  # 自动凭证选科目时优先币种精确匹配，标了 CNY 的科目会实际入账，从对平里剔掉就是一笔解释不了的永久差额。
  def ledger_balance(types, balances)
    wanted = Array(types)
    balances.reject { |row| row[:account].is_group? }
            .select { |row| wanted.include?(row[:account].account_type) }
            .select { |row| row[:account].currency.blank? || row[:account].currency == 'CNY' }
            .sum { |row| row[:closing_micros] }
  end

  def business_balance(key)
    case key
    when 'receivable'
      # 只取本位币台账：总账侧取的也是本位币科目（currency 为空的），外币台账原币与之不可比。
      cny = @account.erp_receivables.where(currency: 'CNY')
      cny.sum(:total_amount_micros) - cny.sum(:received_amount_micros)
    when 'payable'
      cny = @account.erp_payables.where(currency: 'CNY')
      cny.sum(:total_amount_micros) - cny.sum(:paid_amount_micros)
    else
      @account.erp_cash_accounts.active.where(currency: 'CNY').sum(&:balance_micros)
    end
  end
end
