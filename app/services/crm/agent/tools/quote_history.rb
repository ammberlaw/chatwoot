# 这个客户（或这个型号）以前报过什么价、成交过什么价。
#
# 做新报价前必须看一眼：同一个客户去年报 48.5、今年报 52，客户翻出旧邮件就吵起来；
# 不同客户之间报价差太多也是事故。产品档案上那个售价只是挂牌价，真实成交价在
# 历史 PI 和历史订单的明细里。
#
# 取两处：PI 明细（报过的价，含没成交的）＋ 销售订单明细（真成交的价）。
# ⚠️ 不碰订单上的成本/毛利字段。
class Crm::Agent::Tools::QuoteHistory < Crm::Agent::Tools::Base
  description '查历史报价与成交价：某个客户以前报过/成交过哪些型号什么价，或某个型号在各客户那里报过什么价。做新报价、核对价格一致性时用。'
  param :customer_id, type: 'integer', desc: '客户ID，查这个客户的历史价', required: false
  param :keyword, desc: '型号/产品名关键词，查这个型号报过的价', required: false
  param :limit, type: 'integer', desc: '每一类最多列几条，默认 12', required: false

  def execute(customer_id: nil, keyword: nil, limit: 12)
    return '请给客户ID或型号关键词（给了客户ID就查他的历史价）。' if customer_id.blank? && keyword.blank?

    n = [limit.to_i, 30].min
    pi_rows = from_pis(customer_id, keyword, n)
    order_rows = from_orders(customer_id, keyword, n)
    return '在你能看到的 PI 和订单里没查到相关的历史价。' if pi_rows.empty? && order_rows.empty?

    [block('报过的价（来自 PI / 报价单）', pi_rows), block('成交的价（来自销售订单明细）', order_rows)].compact_blank.join("\n\n")
  end

  private

  def block(title, rows)
    rows.empty? ? nil : "【#{title}】\n#{rows.map { |r| "— #{r}" }.join("\n")}"
  end

  def from_pis(customer_id, keyword, limit)
    pis = scope.pis.includes(:pi_items, :crm_customer).order(pi_date: :desc, id: :desc)
    pis = pis.where(crm_customer_id: customer_id.to_i) if customer_id.present?
    pis.limit(60).flat_map { |doc| pi_lines(doc, keyword) }.first(limit)
  end

  def pi_lines(doc, keyword)
    doc.pi_items.select { |item| match?(keyword, item.model, item.description) }.map do |item|
      "#{day(doc.pi_date)}｜#{doc.crm_customer&.name || doc.buyer_company}｜#{item.model}｜" \
        "#{clip(item.description, 40)}｜#{qty_text(item.quantity)} × " \
        "#{money(item.unit_price_micros, doc.currency.presence || 'USD')}｜#{doc.pi_no}（#{doc.status}）"
    end
  end

  def from_orders(customer_id, keyword, limit)
    orders = scope.sales_orders.dealt.includes(:crm_customer).order(order_date: :desc, id: :desc)
    orders = orders.where(crm_customer_id: customer_id.to_i) if customer_id.present?
    orders.limit(60).flat_map { |order| order_lines(order, keyword) }.first(limit)
  end

  def order_lines(order, keyword)
    cur = order.order_currency.presence || 'CNY'
    order.line_item_rows.select { |row| match?(keyword, row[:sku], row[:name]) }.map do |row|
      # 老单子的明细多半没存编码，只有品名里写着型号——空的那格直接不摆，别留个孤零零的「—」。
      cells = [day(order.order_date), order.crm_customer&.name || '—', row[:sku].presence,
               clip(row[:name], 40), "#{qty_text(row[:quantity])} × #{unit_price(row, cur)}", order.order_no]
      cells.compact_blank.join('｜')
    end
  end

  # 明细里的单价不是 micros，是直接存的数（见 Crm::SalesOrder#line_item_rows）。
  def unit_price(row, currency)
    price = row[:unit_price].to_d
    price.zero? ? '单价未填' : money((price * 1_000_000).round, currency)
  end

  # 数量为空/为零是「这行没填数量」，不是「订了 0 个」——写 0 个会让模型照着算错总价。
  def qty_text(value)
    value.to_d.positive? ? "#{fnum(value)} 个" : '数量未填'
  end

  # 没给关键词就全要（按客户查的场景）；给了就在型号和品名里找。
  def match?(keyword, *fields)
    return true if keyword.blank?

    kw = keyword.to_s.strip.downcase
    fields.compact.any? { |f| f.to_s.downcase.include?(kw) }
  end
end
