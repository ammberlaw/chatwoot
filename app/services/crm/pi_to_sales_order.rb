# PI 付款自动转销售订单：PI 状态改「已付款」时把 PI 落成一张销售订单。
# 口径：已付款=已成单，直接落「生产中」（跳过待确认）；金额取明细净额、运费单列；
# 明细/客户/负责人/币种全带过来；并把 PI 的 Excel 附到订单上（单据留痕）。
# 幂等：同一 PI（按 pi_no）只转一次，重复调用返回已存在的订单。
class Crm::PiToSalesOrder
  XLSX_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

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
      status: 'IN_PRODUCTION',
      order_date: Time.current,
      order_currency: @pi.currency,
      order_amount_micros: net_amount_micros,
      shipping_micros: @pi.shipping_cost_micros,
      line_items: line_items,
      remark: "由 PI「#{@pi.pi_no}」付款自动生成"
    )
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
