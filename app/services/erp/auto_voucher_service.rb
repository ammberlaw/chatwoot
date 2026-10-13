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
  REVENUE_CODE = '6001'.freeze       # 主营业务收入
  COGS_CODE = '6401'.freeze          # 主营业务成本
  OUTPUT_TAX_CODE = '22210105'.freeze # 应交税费-应交增值税-销项税额

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

  # ── 销售出库：收入 ────────────────────────────────────────────────
  # 借 应收账款(按币种) 订单金额 / 贷 主营业务收入(不含税) + 贷 销项税额
  #
  # 金额取**销售订单**，不取出库单：出库单上没有价（仓管不该看价），而订单明细行
  # 一行都没挂产品档案（生产实测 743 行全空），按行匹配单价这条路走不通。
  # 故按整单口径——外贸基本整柜一次发，生产上出库单与订单正好 1:1。
  #
  # 防重复记收入：一张销售订单只认第一张出库单。后续出库单只走成本，
  # 收入部分留给财务手工处理——宁可少记也不能把收入记两遍。
  def for_shipment_revenue(shipment)
    return if skip_doc?(Erp::AutoVoucherRule::SHIPMENT_REVENUE)

    order = shipment.crm_sales_order
    return unless revenue_bookable?(shipment, order)

    receivable = order_party_account(order, 'RECEIVABLE')
    revenue = account_by_code(REVENUE_CODE)
    return if receivable.blank? || revenue.blank?

    lines = revenue_lines(order, receivable, revenue)

    create_voucher!(source_type: shipment.class.name, source_id: shipment.id,
                    date: shipment.shipped_at || Time.current,
                    summary: "销售出库 #{shipment.shipment_no} · #{order.order_no}", lines: lines)
  end

  # 金额判定走 gross_sales_micros（货款 + 运费）：生产上有 4 张订单金额为 0、
  # 只有运费（代收代付的那种），按订单金额判就被当成空单跳过、一分钱都不入账。
  def revenue_bookable?(shipment, order)
    order.present? && order.gross_sales_micros.positive? && first_shipment_of_order?(shipment)
  end

  # 收入分录：借 应收账款(全额) / 贷 收入(不含税) + 贷 销项税。
  # 外币下贷方各行 round(原币×汇率) 之和未必等于借方 round(合计×汇率)，
  # 用借方 base 倒挤最后一个贷方行，保证严格相等（同 for_receipt 的处理）。
  def revenue_lines(order, receivable, revenue)
    tax_rate = order.effective_tax_rate
    # 拆税口径放在订单模型上（Crm::SalesOrder#tax_split）——应收台账建账金额要用同一个，
    # 两边各算一套必然在不含税单上差出一个税额。
    net, tax = order.tax_split
    # 应收恒等于「收入 + 销项税」——客户实付的就是这个数（货款 + 运费 + 税）。
    # 含税单它等于订单金额+运费；不含税单那个数只是收入，税要另加，不能照搬金额当应收。
    gross = net + tax
    tax_account = tax.positive? ? account_by_code(OUTPUT_TAX_CODE) : nil

    lines = [doc_line(account: receivable, direction: 'DEBIT', amount_micros: gross, order: order,
                      summary: '应收货款', dimension: { crm_customer_id: order.crm_customer_id }),
             doc_line(account: revenue, direction: 'CREDIT', amount_micros: net, order: order,
                      summary: '确认销售收入')]
    if tax_account.present?
      lines << doc_line(account: tax_account, direction: 'CREDIT', amount_micros: tax, order: order,
                        summary: "销项税额 #{tax_rate}%")
    end
    balance_last_credit!(lines, gross, order.exchange_rate.presence || 1)
    lines
  end

  # ── 应收建账：没走 MES 出库的订单补收入凭证 ──────────────────────
  # 收入的正常触发点是销售出库（财务 2026-10-06 定）。但小满迁进来的、以及走系统外
  # 发货的历史订单在 MES 里**压根没有出库单**，那个触发点永远等不到——建了应收台账，
  # 总账里却没有对应的收入与应收，两账必然对不平。
  #
  # 故：订单已出货/已完结时，建账即按同一套分录出收入凭证（口径与出库那张完全一致，
  # 共用 revenue_lines）。待出货的订单不出——货没发就确认收入是提前确认。
  REVENUE_ON_BUILD_STATUSES = %w[SHIPPED COMPLETED].freeze

  def for_receivable_revenue(receivable)
    return if revenue_voucher_blocker(receivable).present?

    order = receivable.crm_sales_order
    create_voucher!(source_type: receivable.class.name, source_id: receivable.id,
                    date: revenue_date_for(order, receivable),
                    summary: "应收建账 #{receivable.receivable_no} · #{order.order_no}",
                    lines: revenue_lines(order, order_party_account(order, 'RECEIVABLE'), account_by_code(REVENUE_CODE)))
  end

  # 出不了收入凭证的原因，能出就返回 nil。台账上的「补出凭证」要把原因原样说给财务听，
  # 不然点一下没动静只能靠猜。建账时的自动生成走同一套判断，两边口径不会分叉。
  def revenue_voucher_blocker(receivable)
    return '自动凭证规则「销售出库 → 收入」已停用' if skip_doc?(Erp::AutoVoucherRule::SHIPMENT_REVENUE)

    # 出库单上那张也算在内（见 Erp::Receivable#revenue_voucher）——同一笔收入不能入两次账。
    existing = receivable.revenue_voucher
    return "已经有收入凭证 #{existing.voucher_no}" if existing
    return '这条台账没挂销售订单' if receivable.crm_sales_order.blank?

    order_revenue_blocker(receivable.crm_sales_order)
  end

  def order_revenue_blocker(order)
    return '订单金额为 0' if order.gross_sales_micros <= 0
    return "订单还是「#{Crm::SalesOrder::STATUS_LABELS[order.status] || order.status}」，发货后才确认收入" \
      unless REVENUE_ON_BUILD_STATUSES.include?(order.status)
    return '账套里找不到应收账款科目' if order_party_account(order, 'RECEIVABLE').blank?

    "账套里找不到主营业务收入科目（#{REVENUE_CODE}）" if account_by_code(REVENUE_CODE).blank?
  end

  # 收入确认日取交期（货实际发出的时点）；没填交期的历史单回落下单日，
  # 两者都没有才用建账日——总得落在某个会计期间里。
  def revenue_date_for(order, receivable)
    order.delivery_date || order.order_date || receivable.created_at
  end

  # ── 销售出库：成本结转 ────────────────────────────────────────────
  # 借 主营业务成本 / 贷 库存商品。金额取 StockCostService 已按 FIFO 结转进
  # erp_order_costs 的那笔（人民币），不再重算——重算必然和存货层对不上。
  # 与收入凭证共用来源单据，靠 source_type 后缀区分成两张（财务要的就是两笔）。
  COST_SOURCE_SUFFIX = '::Cost'.freeze

  def for_shipment_cost(shipment)
    return if skip_doc?(Erp::AutoVoucherRule::SHIPMENT_COST)

    amount = shipment_cost_micros(shipment)
    return if amount <= 0

    cogs = account_by_code(COGS_CODE)
    inventory = account_by_code(Erp::Setting::FINISHED_GOODS_CODE)
    return if cogs.blank? || inventory.blank?

    lines = [cny_line(account: cogs, direction: 'DEBIT', amount_micros: amount, summary: '结转销售成本'),
             cny_line(account: inventory, direction: 'CREDIT', amount_micros: amount, summary: '发出库存商品')]

    create_voucher!(source_type: "#{shipment.class.name}#{COST_SOURCE_SUFFIX}", source_id: shipment.id,
                    date: shipment.shipped_at || Time.current,
                    summary: "结转成本 #{shipment.shipment_no}", lines: lines)
  end

  # 成本金额＝该销售订单归集到的**全部**成本行（本位币合计），与毛利表同一口径
  # （Erp::MarginService 也是按 crm_sales_order_id 取全部行，含手工补录的运费/佣金）。
  # 两边不同口径，利润表的成本和毛利表的成本必然对不上。
  #
  # 原先只认 source_type='Mes::Shipment' 的行——那是现货轨道的成本来源。定制单的成本
  # 由 CostRollupService 按领料/外协归集，挂在**生产订单**名下，出库单身上一条都没有，
  # 于是定制单出库永远结转不出成本凭证（生产上已出库的 12 张全是定制单：收入记了、
  # 成本没记，毛利虚高）。按订单取，把两条轨道收口到同一个口径上。
  #
  # 分批发货整笔成本挂第一张出库单，不按数量分摊——收入侧就是整单口径
  # （见 first_shipment_of_order?），成本跟着同一口径两边才对得上。
  def shipment_cost_micros(shipment)
    return orphan_shipment_cost_micros(shipment) if shipment.crm_sales_order_id.blank?
    # 订单已软删（default_scope 过滤掉，关联读不到）：收入凭证也不会出
    # （revenue_bookable? 里 order 为 nil 就返回 false），成本跟着不出——
    # 否则总账上只有成本没有收入，比两边都没有更糟。
    return 0 if shipment.crm_sales_order.blank?
    return 0 unless first_shipment_of_order?(shipment)

    order_cost_sum(@account.erp_order_costs.where(crm_sales_order_id: shipment.crm_sales_order_id))
  end

  # 没挂销售订单的出库单（历史数据 / 系统外发货）：按订单取数无从下手，
  # 退回只认挂在它自己和它那张生产订单名下的归集行。
  def orphan_shipment_cost_micros(shipment)
    scope = @account.erp_order_costs.where(source_type: shipment.class.name, source_id: shipment.id)
    if shipment.production_order_id.present?
      scope = scope.or(@account.erp_order_costs.where(source_type: 'Mes::ProductionOrder',
                                                      source_id: shipment.production_order_id))
    end
    order_cost_sum(scope)
  end

  # 折本位币再求和：成本行带币种与汇率，裸 sum 原币会把不同币种直接相加（守卫 spec 盯着这个）。
  def order_cost_sum(scope)
    scope.sum(Arel.sql(Erp::OrderCost::BASE_AMOUNT_MICROS_SQL)).to_i
  end

  # ── 采购入库 / 退货 ──────────────────────────────────────────────
  # 借 存货科目(按来源类别映射，逐类合并) / 贷 应付账款(按币种)。
  # 退货走红字：金额取负，不做反向分录（财务 2026-10-06 明确「退货是红字冲销法」）。
  def for_stock_receipt(entry)
    return if skip_doc?(Erp::AutoVoucherRule::STOCK_RECEIPT)

    rows = stock_receipt_rows(entry)
    payable = cny_payable_account
    return if rows.blank? || payable.blank?

    lines = stock_receipt_lines(entry, rows, payable)
    return if lines.size < 2

    create_voucher!(source_type: entry.class.name, source_id: entry.id,
                    date: entry.posted_at || entry.created_at,
                    summary: "#{return_entry?(entry) ? '采购退货' : '采购入库'} #{entry.entry_no}",
                    lines: lines)
  end

  def return_entry?(entry) = entry.purpose == 'MATERIAL_RETURN'

  def cny_payable_account
    scope = @account.erp_ledger_accounts.active.leaves.where(account_type: 'PAYABLE')
    scope.find_by(currency: nil) || scope.first
  end

  # 入库：借 存货科目（按来源类别合并） / 贷 应付账款（按供应商合并，往来科目必须带维度）。
  # 退货：借贷方向整体对调。
  #
  # 为什么不用负数走红字：分录行校验卡死 amount_micros >= 0、base > 0，
  # 负数根本存不进去；而系统既有的红冲（VoucherPostingService）本来就是方向镜像，
  # 这里跟着同一套约定，科目余额的结果与红字完全一致。
  def stock_receipt_lines(entry, rows, payable)
    swap = return_entry?(entry)
    lines = stock_side_lines(rows, swap)
    return lines if lines.blank?

    lines + payable_side_lines(rows, payable, swap)
  end

  def stock_side_lines(rows, swap)
    rows.group_by { |r| r[:code] }.filter_map do |code, group|
      acc = account_by_code(code)
      next if acc.blank?

      cny_line(account: acc, direction: swap ? 'CREDIT' : 'DEBIT',
               amount_micros: group.sum { |r| r[:amount] },
               summary: swap ? '采购退货冲回存货' : '采购入库')
    end
  end

  def payable_side_lines(rows, payable, swap)
    rows.group_by { |r| r[:supplier_id] }.map do |supplier_id, group|
      cny_line(account: payable, direction: swap ? 'DEBIT' : 'CREDIT',
               amount_micros: group.sum { |r| r[:amount] },
               summary: swap ? '冲减应付' : '应付采购款',
               dimension: { mes_supplier_id: supplier_id })
    end
  end

  # 内部划转：借 转入账户 / 贷 转出账户（跨币种的汇兑差额在 §7.2 落地后再补）。
  # attrs: { amount_micros:, happened_at:, source_key:, rate: }
  # rate：同币种外币互转按划转日汇率折本位币（两腿同率必平），CNY 恒为 1。
  def for_transfer(from_account, to_account, attrs)
    rule = rule_for(Erp::AutoVoucherRule::CASH_TRANSFER)
    return if rule.blank? || !rule.is_active?
    return if from_account.ledger_account.blank? || to_account.ledger_account.blank?

    rate = attrs.fetch(:rate, 1)
    lines = [
      { ledger_account_id: to_account.ledger_account_id, direction: 'DEBIT', amount_micros: attrs[:amount_micros],
        summary: "转入 #{to_account.name}", currency: to_account.currency, exchange_rate: rate },
      { ledger_account_id: from_account.ledger_account_id, direction: 'CREDIT', amount_micros: attrs[:amount_micros],
        summary: "转出 #{from_account.name}", currency: from_account.currency, exchange_rate: rate }
    ]
    create_voucher!(source_type: 'Erp::CashTransfer', source_id: attrs[:source_key], date: attrs[:happened_at],
                    summary: "内部划转 #{from_account.name} → #{to_account.name}", lines: lines)
  end

  # 报销打款：借 费用科目 / 贷 货币资金。报销恒为本位币，不涉及外币倒挤。
  # ── 备用金台账 → 凭证 ───────────────────────────────────────
  # 公司打钱给保管人（IN）＝ 借 备用金 / 贷 资金；保管人花出去（OUT）＝ 借 费用 / 贷 备用金。
  # 备用金科目默认科目表里没有（1221 其他应收款是父级、不能记账），要财务先建一个叶子科目
  # 再到「自动凭证规则」里配上；没配就静默跳过——台账照常记，不挡业务。
  def for_petty_cash(entry)
    event = entry.direction == 'IN' ? Erp::AutoVoucherRule::PETTY_CASH_IN : Erp::AutoVoucherRule::PETTY_CASH_OUT
    return if skip_doc?(event)

    petty = petty_cash_ledger_account(event)
    other = entry.direction == 'IN' ? petty_fund_account(event, entry) : petty_expense_account(entry)
    return if petty.blank? || other.blank?

    build_voucher(entry, petty_summary(entry), entry.entry_date, petty_lines(entry, petty, other))
  end

  def for_expense_payout(payout)
    return if skip?(Erp::AutoVoucherRule::EXPENSE_PAYOUT, payout)

    cash = cash_account_for(payout)
    expense = payout.expense_ledger_account
    return if cash.blank? || expense.blank?

    lines = [
      line(account: expense, direction: 'DEBIT', amount_micros: payout.amount_micros, record: payout,
           summary: '报销费用'),
      line(account: cash, direction: 'CREDIT', amount_micros: payout.amount_micros, record: payout,
           summary: '支付报销款')
    ]
    build_voucher(payout, "报销 #{payout.payout_no} · #{payout.applicant&.name}", payout.paid_at, lines)
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

  # IN：借 备用金 / 贷 资金；OUT：借 费用 / 贷 备用金。
  def petty_lines(entry, petty, other)
    micros = (entry.amount.to_d * 1_000_000).round
    debit, credit = entry.direction == 'IN' ? [petty, other] : [other, petty]
    [
      line(account: debit, direction: 'DEBIT', amount_micros: micros, record: entry,
           summary: entry.subject.to_s.presence || '备用金'),
      line(account: credit, direction: 'CREDIT', amount_micros: micros, record: entry,
           summary: entry.direction == 'IN' ? "拨付备用金（#{entry.channel.presence || '现金'}）" : '冲减备用金')
    ]
  end

  def petty_summary(entry)
    who = entry.book&.name.presence || entry.handler&.name
    ['备用金', entry.direction == 'IN' ? '存入' : '支出', who, entry.subject].compact_blank.join(' · ')
  end

  # 备用金挂账科目：规则里配了就用配的，没配回落国标科目表的 1221 其他应收款
  # （生产上 1221 就是可记账的叶子，不用额外建子科目；财务想细分再建、建完到规则里配）。
  PETTY_CASH_DEFAULT_CODE = '1221'.freeze

  def petty_cash_ledger_account(event)
    id = rule_for(event)&.config&.dig('petty_cash_account_id')
    return @account.erp_ledger_accounts.active.leaves.find_by(id: id) if id.present?

    leaf_by_code(PETTY_CASH_DEFAULT_CODE)
  end

  def leaf_by_code(code)
    acc = account_by_code(code)
    acc&.is_group? ? nil : acc
  end

  # 存入的资金来源按渠道挑：现金走 CASH，其余（银行/支付宝/微信）走 BANK；配了就用配的。
  def petty_fund_account(event, entry)
    cfg = rule_for(event)&.config || {}
    key = entry.channel == '现金' ? 'cash_account_id' : 'bank_account_id'
    configured = cfg[key].presence
    return @account.erp_ledger_accounts.active.leaves.find_by(id: configured) if configured

    type = entry.channel == '现金' ? 'CASH' : 'BANK'
    @account.erp_ledger_accounts.active.leaves.where(account_type: type).order(:code).first
  end

  # 支出的费用科目按费用类别挑：规则里配了用配的，没配按国标科目表的编码对应。
  # 「交通」没有独立科目，并进差旅费；「其他」与未填类别进其他管理费用。
  PETTY_EXPENSE_KEYS = { '差旅' => 'expense_travel_id', '招待' => 'expense_entertain_id',
                         '办公' => 'expense_office_id', '交通' => 'expense_transport_id' }.freeze
  PETTY_EXPENSE_CODES = { '差旅' => '660104', '招待' => '660103',
                          '办公' => '660202', '交通' => '660104' }.freeze
  PETTY_EXPENSE_FALLBACK_CODE = '660299'.freeze

  def petty_expense_account(entry)
    cfg = rule_for(Erp::AutoVoucherRule::PETTY_CASH_OUT)&.config || {}
    id = cfg[PETTY_EXPENSE_KEYS[entry.category]].presence || cfg['expense_account_id'].presence
    return @account.erp_ledger_accounts.active.leaves.find_by(id: id) if id

    leaf_by_code(PETTY_EXPENSE_CODES[entry.category] || PETTY_EXPENSE_FALLBACK_CODE) ||
      leaf_by_code(PETTY_EXPENSE_FALLBACK_CODE)
  end

  # 找不到该事件的规则就补建一次默认规则再找。
  # ⚠️ 原来只在规则表**整个为空**时才建：老账号已有前几条规则，后来新增的事件（如报销打款）
  # 永远补不到规则，凭证静默不生成——业务照走、总账少一张，等对账时才发现。
  # ensure_defaults! 是 find_or_create_by! 幂等，不会动财务已改过的启用状态与科目映射。
  def rule_for(event_key)
    rule = @account.erp_auto_voucher_rules.find_by(event_key: event_key)
    return rule if rule

    Erp::AutoVoucherRule.ensure_defaults!(@account)
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

  # 单据类事件没有 cash_account_id，不能复用 skip?（它拿现金账户判空）。
  def skip_doc?(event_key)
    rule = rule_for(event_key)
    rule.blank? || !rule.is_active?
  end

  def account_by_code(code)
    @account_by_code ||= {}
    @account_by_code[code] ||= @account.erp_ledger_accounts.find_by(code: code)
  end

  # 销售订单的往来科目按订单币种挑（人民币走 112201、美金走 112202）。
  def order_party_account(order, type)
    scope = @account.erp_ledger_accounts.active.leaves.where(account_type: type)
    scope.find_by(currency: order.order_currency) || scope.find_by(currency: nil) || scope.first
  end

  # 把订单金额拆成「不含税收入 + 销项税」。含不含税按**单据**上转单时勾的那个来
  # （同一家公司两种合同都有，账套设置只当默认值）。
  # 税率 0（出口免税）两种算法同值，直接返回原额 + 0 税。
  # 一张销售订单只认第一张出库单（按出库单 id 取最早的一张，不看凭证是否已作废，
  # 否则作废重开会把收入记第二遍）。收入与成本共用这个判断，保证两边同口径。
  def first_shipment_of_order?(shipment)
    first = @account.mes_shipments.where(crm_sales_order_id: shipment.crm_sales_order_id)
                    .where.not(status: 'CANCELLED').order(:id).first
    first.nil? || first.id == shipment.id
  end

  # 订单币种下的分录行（单据没有 currency/exchange_rate 属性，这里显式给）。
  def doc_line(spec)
    {
      ledger_account_id: spec[:account].id, direction: spec[:direction], amount_micros: spec[:amount_micros],
      summary: spec[:summary], currency: spec[:order].order_currency.presence || 'CNY',
      exchange_rate: spec[:order].exchange_rate.presence || 1
    }.merge(spec[:dimension] || {})
  end

  # 本位币分录行（成本与入库都已折成人民币）。
  def cny_line(spec)
    {
      ledger_account_id: spec[:account].id, direction: spec[:direction], amount_micros: spec[:amount_micros],
      summary: spec[:summary], currency: 'CNY', exchange_rate: 1
    }.merge(spec[:dimension] || {})
  end

  # 外币下逐行 round 之和会和借方差几分，用借方 base 倒挤最后一个贷方行。
  def balance_last_credit!(lines, gross, rate)
    debit_base = Erp::VoucherLine.round_to_cent(gross * rate.to_d)
    credits = lines.select { |l| l[:direction] == 'CREDIT' }
    return if credits.empty?

    others = credits[0..-2].sum { |l| Erp::VoucherLine.round_to_cent(l[:amount_micros] * rate.to_d) }
    credits.last.merge!(base_amount_micros: debit_base - others, explicit_base: true)
  end

  # 入库单按「产品的来源类别 → 存货科目」把金额分桶，同科目合并成一行。
  #
  # 入库明细行上没有金额（只有数量），价从**关联采购单**的同产品行取——
  # 与 StockCostService 建批次层用的是同一个价，否则存货层和凭证会对不上。
  # 取不到价（无采购单、或该产品不在采购单上）的行跳过：宁可不出凭证，
  # 也不能按 0 入账把存货做没。
  def stock_receipt_rows(entry)
    setting = Erp::Setting.for_account(@account)
    po_lines = entry.purchase_order&.purchase_items || []
    entry.stock_entry_items.filter_map { |item| stock_receipt_row(setting, po_lines, item) }
  end

  def stock_receipt_row(setting, po_lines, item)
    po_line = po_lines.find { |pi| pi.crm_product_id.present? && pi.crm_product_id == item.crm_product_id }
    amount = purchase_amount_for(po_line, item)
    return if amount <= 0

    { code: setting.inventory_account_code_for(item.crm_product&.source_category),
      supplier_id: po_line.mes_supplier_id, amount: amount }
  end

  # 本次入库数量 × 采购单价（采购行金额 ÷ 采购数量）。
  def purchase_amount_for(line, item)
    return 0 if line.nil? || line.amount_micros.blank? || line.qty.to_d <= 0

    received = (item.received_qty.presence || item.qty).to_d
    Erp::VoucherLine.round_to_cent(received * (line.amount_micros / line.qty.to_d))
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
  def guard_posted!(previous, lines, date)
    return previous if signature(previous.lines) == signature(lines) && previous.voucher_date == date&.to_date

    raise Error, "本单已生成凭证 #{previous.voucher_no} 并已记账，改动不会自动同步到凭证。" \
                 '请先红冲该凭证，再修改单据。'
  end

  # 汇率/币种必须进签名：只改汇率（或币种撞到同一兜底科目）时分录原币没变，
  # 但本位币 base 全变了——不进签名就静默放行，总账停在旧汇率、台账/流水按新汇率走，又是一类静默不平。
  # 日期同理（决定凭证期间），在 guard_posted! 里单独比。
  SIGNATURE_KEYS = %i[ledger_account_id direction amount_micros currency exchange_rate crm_customer_id mes_supplier_id].freeze

  def signature(lines)
    lines.map do |line|
      SIGNATURE_KEYS.map do |key|
        value = line.is_a?(Hash) ? line[key] : line.public_send(key)
        key == :exchange_rate ? value.to_d : value
      end
    end.sort_by(&:to_s)
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
        guard_posted!(previous, lines, date)
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
