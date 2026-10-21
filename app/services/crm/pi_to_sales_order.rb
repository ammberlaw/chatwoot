# PI 付款自动转销售订单：PI 状态改「已付款」时把 PI 落成一张销售订单。
# 口径：已付款=已成单，直接落「生产中」（跳过待确认）；金额取明细净额、运费单列；
# 明细/客户/负责人/币种全带过来；并把 PI 的 Excel 附到订单上（单据留痕）。
# 幂等：同一 PI（按 pi_no）只转一次，重复调用返回已存在的订单。
class Crm::PiToSalesOrder
  XLSX_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

  # PI 抬头 → 资金账户名：客户是照 PI 上印的 BANK DETAILS 打款的，收哪个账户在开 PI 时就定了，
  # 转单时按抬头带过来，不用人再选一次。账户按名字找，账套里没有这个名字就留空（不猜）。
  # 转单后需要人补的结算信息（前端据此决定要不要弹补填框）。
  SETTLEMENT_FIELDS = %i[payment_term receipt_account_id insurance_order_no].freeze

  RECEIPT_ACCOUNT_BY_HEADER = {
    'HK_WINTOUCH' => '香港建设银行',
    'DG_LIONTEK' => '东莞联迪建设银行'
  }.freeze

  def initialize(pi_record)
    @pi = pi_record
    @account = pi_record.account
  end

  # 返回转出的（或已存在的）销售订单；无法转（无单号）时返回 nil。
  def call
    return if @pi.pi_no.blank?

    existing = @account.crm_sales_orders.find_by(pi_no: @pi.pi_no)
    return existing if existing

    order = build_order
    order.system_generated = true
    order.save!
    attach_pi_excel(order)
    order
  end

  private

  def build_order
    @account.crm_sales_orders.new(
      name: @pi.pi_no,
      pi_no: @pi.pi_no,
      crm_customer_id: @pi.crm_customer_id,
      contact_id: @pi.contact_id,
      owner_id: @pi.owner_id,
      handled_by_id: @pi.handled_by_id,
      # 付了钱 ≠ 已经在做。原来这里直接置「生产中」，于是 PI 一付款订单就显示在产，
      # MES 里却一张生产单/出库单都没有——没人知道这单还等着转，生产上 62 张
      # 「看着在产、实际没人做」的单，主力就是这么来的（2026-10-21）。
      # 改为「待确认」：转单（定制→生产单 / 库存→出库单）真正发生时才进生产中。
      status: 'PENDING_CONFIRMATION',
      order_date: Time.current,
      order_currency: @pi.currency,
      order_amount_micros: net_amount_micros,
      shipping_micros: @pi.shipping_cost_micros,
      receipt_account_id: receipt_account_id,
      line_items: line_items,
      remark: "由 PI「#{@pi.pi_no}」付款自动生成"
    )
  end

  # 收款账户：按 PI 抬头对应的那个银行账户。
  # **结算方式和信保订单号不在这里猜**——PI 的付款条款是自由文本（"T/T 30% deposit…"
  # 和 "BANK / Alibaba" 都可能），猜错了会一路错到应收台账，由人在转单后补填。
  def receipt_account_id
    name = RECEIPT_ACCOUNT_BY_HEADER[@pi.company_header]
    return if name.blank?

    @account.erp_cash_accounts.find_by(name: name)&.id
  end

  # 订单金额=净销售（不含运费）：优先取明细金额合计；无明细则退回 PI 总额。
  def net_amount_micros
    items_total = @pi.pi_items.sum { |item| item.amount_micros.to_i }
    items_total.positive? ? items_total : @pi.total_amount_micros.to_i
  end

  def line_items
    @pi.pi_items.map do |item|
      {
        # PI 明细选过产品就带下来——订单侧不用再匹配一次（这是 PI 加产品关联的全部意义）。
        crm_product_id: item.crm_product_id,
        # 型号单独留一份：原来只塞进 name，订单侧就分不出「这是型号」还是「客户写的品名」。
        model: item.model,
        name: item.model.presence || item.description.to_s,
        spec: item.description,
        quantity: item.quantity,
        unit_price: micros_to_num(item.unit_price_micros),
        amount: micros_to_num(item.amount_micros)
      }
    end
  end

  def micros_to_num(micros)
    return nil if micros.nil?

    (micros / 1_000_000.0)
  end

  # 尽力把 PI 的 Excel 附到订单：卖方落款缺失（导不出）时静默跳过，订单照建。
  def attach_pi_excel(order)
    return if [@pi.issued_by, @pi.seller_mobile, @pi.seller_email].any?(&:blank?)

    stream = Crm::PiTemplateFiller.new(@pi).to_stream
    stream.rewind if stream.respond_to?(:rewind)
    order.files.attach(io: stream, filename: "PI-#{@pi.pi_no}.xlsx", content_type: XLSX_TYPE)
  rescue StandardError => e
    Rails.logger.error("[PiToSalesOrder] attach xlsx failed pi=#{@pi.id}: #{e.class} #{e.message}")
  end
end
