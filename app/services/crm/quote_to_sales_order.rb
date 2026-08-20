# 报价确认后一键转销售订单：把报价单落成一张销售订单（待确认阶段，业务再推进）。
# 口径：金额取明细净额、运费单列；明细/客户/负责人/币种全带过来。
# 幂等：同一报价（按 crm_quote_id）只转一次，重复调用返回已存在的订单。
class Crm::QuoteToSalesOrder
  def initialize(quote_record)
    @quote = quote_record
    @account = quote_record.account
  end

  # 返回转出的（或已存在的）销售订单；无法转时返回 nil。
  def call
    existing = @account.crm_sales_orders.find_by(crm_quote_id: @quote.id)
    return existing if existing

    order = build_order
    order.skip_attachment_check = true if order.respond_to?(:skip_attachment_check=)
    order.save!
    order
  end

  private

  def build_order
    @account.crm_sales_orders.new(
      name: @quote.name.presence || @quote.quote_no,
      crm_quote_id: @quote.id,
      crm_customer_id: @quote.crm_customer_id,
      contact_id: @quote.contact_id,
      owner_id: @quote.owner_id,
      handled_by_id: @quote.handled_by_id,
      status: 'PENDING_CONFIRMATION',
      order_date: Time.current,
      order_currency: @quote.quote_currency,
      order_amount_micros: net_amount_micros,
      shipping_micros: @quote.shipping_fee_micros,
      line_items: line_items,
      remark: "由报价单「#{@quote.quote_no}」转入"
    )
  end

  # 订单金额=净销售（不含运费）：优先取明细金额合计；无明细则退回报价小计/总额。
  def net_amount_micros
    items_total = @quote.line_items.sum { |item| item.amount_micros.to_i }
    return items_total if items_total.positive?

    @quote.subtotal_micros.to_i.positive? ? @quote.subtotal_micros.to_i : @quote.total_amount_micros.to_i
  end

  def line_items
    @quote.line_items.map do |item|
      {
        name: item.name.presence || item.product_name_snapshot.to_s,
        spec: item.spec_snapshot,
        quantity: item.quantity,
        unit_price: micros_to_num(item.unit_price_micros),
        amount: micros_to_num(item.amount_micros)
      }
    end
  end

  def micros_to_num(micros)
    return nil if micros.nil?

    micros / 1_000_000.0
  end
end
