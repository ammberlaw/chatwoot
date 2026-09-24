# 销售订单 → ERP（金蝶）销售订单：归一化单据 + 转单前就绪检查。
#
# 为什么检查放在这一步、而不是建单时卡：
# 有一部分定制品的编码是**下单之后**工程/采购才给的，建单当场根本填不出来。
# 在建单接口硬卡会把这类单直接挡在门外（而 PI 付款自动建单那条路外层是
# `rescue StandardError`，一卡就静默失败、订单凭空消失）。所以建单一律放行，
# 等到真要推去金蝶时再算账——那时编码通常已经下来了，缺什么也一目了然。
#
# 本服务只做两件事：把单据摊平成金蝶需要的形状，以及列出还差什么。
# 不生成文件——金蝶导入模板的列名/表头行要以对方模板为准，那部分单独做。
class Crm::ErpOrderExport
  # 阻断项类型 → 给人看的说明。前端按 type 决定跳哪个页面去补。
  BLOCKER_LABELS = {
    customer_code: '客户还没有 ERP 编码',
    payment_term: '收款方式没填',
    line_product: '明细行还没关联产品档案',
    line_product_sku: '关联的产品没有编码',
    line_quantity: '明细行数量为空或为零'
  }.freeze

  def initialize(sales_order)
    @order = sales_order
    @account = sales_order.account
  end

  def call
    { header: header, lines: lines, blockers: blockers, ready: blockers.empty? }
  end

  private

  def header
    {
      order_no: @order.order_no,
      order_date: @order.order_date&.to_date&.to_s,
      delivery_date: @order.delivery_date&.to_date&.to_s,
      customer_name: @order.crm_customer&.name,
      customer_code: @order.crm_customer&.customer_code.presence,
      currency: @order.order_currency,
      exchange_rate: @order.exchange_rate,
      payment_term: @order.payment_term.presence,
      payment_term_label: payment_term_label,
      # 运费金蝶那边通常单列一行或走单据头，先原样带出去，由模板决定落在哪。
      shipping: to_amount(@order.shipping_micros),
      remark: @order.remark.presence,
      owner_name: @order.owner&.name,
      pi_no: @order.pi_no.presence
    }
  end

  def lines
    @lines ||= raw_items.each_with_index.map { |item, index| line_row(item, index) }
  end

  def raw_items
    Array(@order.line_items).select { |i| i.is_a?(Hash) }
  end

  def line_row(item, index)
    product = linked_products[item['crm_product_id'].to_i]
    {
      row: index + 1,
      name: item['name'].to_s,
      spec: item['spec'].presence,
      quantity: item['quantity'],
      unit_price: item['unit_price'],
      amount: item['amount'],
      # 运费/杂费行本来就不是产品，不要求关联（口径与转单弹窗一致）。
      fee: fee_line?(item['name']),
      crm_product_id: product&.id,
      product_sku: product&.sku,
      product_name: product&.name,
      product_spec: product&.specification,
      product_unit: product&.unit
    }
  end

  def linked_products
    @linked_products ||= begin
      ids = raw_items.filter_map { |i| i['crm_product_id'].presence&.to_i }.uniq
      ids.empty? ? {} : @account.crm_products.where(id: ids).index_by(&:id)
    end
  end

  def fee_line?(text)
    text.to_s.match?(Crm::LineItemProductMatcher::FEE_PATTERN)
  end

  def blockers
    @blockers ||= [
      (blocker(:customer_code) if @order.crm_customer&.customer_code.blank?),
      (blocker(:payment_term) if @order.payment_term.blank?),
      rows_blocker(:line_product) { |l| !l[:fee] && l[:crm_product_id].blank? },
      rows_blocker(:line_product_sku) { |l| l[:crm_product_id].present? && l[:product_sku].blank? },
      rows_blocker(:line_quantity) { |l| l[:quantity].to_f <= 0 }
    ].compact
  end

  def blocker(type, rows = [])
    { type: type.to_s, message: BLOCKER_LABELS[type], rows: rows }
  end

  def rows_blocker(type)
    rows = lines.select { |l| yield(l) }.map { |l| l[:row] }
    return nil if rows.empty?

    blocker(type, rows)
  end

  def payment_term_label
    code = @order.payment_term.presence
    return nil if code.blank?

    @account.crm_option_items.for_category('payment_term').find_by(code: code)&.name || code
  end

  def to_amount(micros)
    return nil if micros.blank?

    (micros.to_i / 1_000_000.0).round(2)
  end
end
