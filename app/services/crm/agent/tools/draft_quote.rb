# 建一张报价单草稿——**不发客户、不提交**。
#
# 外贸的单据顺序是「报价单 → 客户确认 → PI → 订单」，agent 以前直接跳到 PI，
# 中间那张最常用的单反而建不了（客户只是问价，还没到开 PI 的程度）。
#
# 和 draft_pi 一样只出草稿（DRAFT），业务员自己去核价格和条款，确认再发。
class Crm::Agent::Tools::DraftQuote < Crm::Agent::Tools::Base
  description '建一张报价单草稿（状态草稿，不会发给客户）。客户只是问价、还没到开 PI 那一步时用这个。做完提醒用户去「报价单」里核对后发出。'
  param :customer_id, type: 'integer', desc: '客户ID'
  # 明细格式和 draft_pi 刻意保持一致：竖线分隔的纯文本。
  # DeepSeek 吐嵌套对象数组时常把 JSON 写坏（实测报 expected ',' or ']'），整次调用直接失败。
  param :items, desc: "明细，一行一项，竖线分隔：型号 | 描述 | 数量 | 单价。例如：\nWT-IPM104 | 10.4寸工业触摸屏 | 50 | 119.04"
  param :currency, desc: '币种，如 USD / EUR / CNY；不传按客户档案的常用币种', required: false
  param :valid_days, type: 'integer', desc: '有效期几天，默认 30（公司报价单惯例）', required: false
  param :remark, desc: '备注/条款，可留空', required: false

  DEFAULT_VALID_DAYS = 30

  def execute(customer_id:, items:, currency: nil, valid_days: nil, remark: nil)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户，没法建报价单。" if customer.nil?

    rows = normalize(items)
    return 'items 没解析出可用明细。每行写成「型号 | 描述 | 数量 | 单价」，数量和单价必须是数字。' if rows.empty?

    quote = build(customer, rows, currency, valid_days, remark)
    scope.record_artifact(kind: 'quote_draft', id: quote.id, customer_id: customer.id,
                          label: "报价单草稿 #{quote.quote_no}")
    summary(quote, rows)
  end

  private

  # 每行金额和合计都在这儿算好一并回去，让模型照抄。
  # 不给它就会自己乘一遍——draft_pi 那边实测把 100 × 268 乘成 33,800（应为 26,800）。
  def summary(quote, rows)
    lines = rows.map.with_index(1) { |row, idx| "#{idx}. #{line_text(row, quote.quote_currency)}" }
    <<~TEXT
      已建报价单草稿 #{quote.quote_no}（#{rows.size} 项，状态草稿、没有发给客户，有效期到 #{day(quote.valid_until)}）。
      明细（金额都已算好，回答时照抄，别自己再乘一遍）：
      #{lines.join("\n")}
      合计 #{money(quote.total_amount_micros, quote.quote_currency)}
      #{self_check(Crm::DocHealthCheck.for_quote(quote))}
      最后提醒用户到「报价单」里核对价格和条款，确认后再发给客户。
    TEXT
  end

  def line_text(row, currency)
    unit = money((row[:price] * 1_000_000).round, currency)
    amount = money((row[:qty] * row[:price] * 1_000_000).round, currency)
    "#{row[:model]} | #{row[:description]} | #{fnum(row[:qty])} × #{unit} = #{amount}"
  end

  def normalize(items)
    items.to_s.split("\n").filter_map do |line|
      cells = line.split('|').map(&:strip)
      next if cells.size < 4

      qty = cells[2].to_d
      price = cells[3].to_d
      next if qty <= 0 || price <= 0

      { model: cells[0], description: cells[1], qty: qty, price: price }
    end
  end

  def build(customer, rows, currency, valid_days, remark)
    quote = scope.account.crm_quotes.new(header_attrs(customer, currency, valid_days, remark))
    rows.each { |row| quote.line_items.build(item_attrs(row)) }
    quote.subtotal_micros = quote.total_amount_micros = rows.sum { |r| (r[:qty] * r[:price] * 1_000_000).round }
    quote.save!
    quote
  end

  def header_attrs(customer, currency, valid_days, remark)
    days = valid_days.to_i.positive? ? valid_days.to_i : DEFAULT_VALID_DAYS
    { crm_customer_id: customer.id, owner_id: customer.account_owner_id || scope.user_id,
      handled_by_id: scope.user_id, status: 'DRAFT', quote_date: Time.current,
      valid_until: days.days.from_now, name: "#{customer.name} 报价单",
      quote_currency: currency.presence || customer.currency_preference.presence || 'USD',
      remark: remark.to_s.presence }
  end

  # 业绩归客户归属人（owner），经办人记自己（handled_by）——同报价单页建单口径。
  def item_attrs(row)
    { account_id: scope.account.id, name: row[:model].presence || row[:description],
      product_name_snapshot: row[:description], spec_snapshot: row[:description],
      quantity: row[:qty], unit_price_micros: (row[:price] * 1_000_000).round,
      amount_micros: (row[:qty] * row[:price] * 1_000_000).round }
  end
end
