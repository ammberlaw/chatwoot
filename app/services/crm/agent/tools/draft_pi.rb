# 建一张 PI / 报价单草稿——**不提交、不发给客户**。
#
# 用户定的规矩：agent 只出草稿。建成 DRAFT 状态放在 PI 模块里，
# 业务员自己去核对价格、交期、条款，确认无误再导出发客户。
class Crm::Agent::Tools::DraftPi < Crm::Agent::Tools::Base
  description '建一张 PI（形式发票/报价单）草稿，状态为草稿、不会发给客户。做完提醒用户去「PI 形式发票」里核对后导出。'
  param :customer_id, type: 'integer', desc: '客户ID'
  # 明细刻意用「一行一项的文本」而不是对象数组：DeepSeek 的 function calling 吐嵌套
  # 对象数组时经常把 JSON 写坏（实测报 expected ',' or ']'），整次调用直接失败。
  # 竖线分隔的纯文本它几乎不会写错，解析也就几行。
  param :items, desc: "明细，一行一项，竖线分隔：型号 | 描述 | 数量 | 单价。例如：\nWT-EDU101 | 10.1寸教育平板 | 500 | 48.5\nWT-IPM156 | 15.6寸工业屏 | 2 | 268"
  param :currency, desc: '币种，如 USD / CNY；不传按客户档案的常用币种', required: false
  param :remark, desc: '备注/条款，可留空', required: false

  def execute(customer_id:, items:, currency: nil, remark: nil)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户，没法建 PI。" if customer.nil?

    rows = normalize(items)
    return 'items 没解析出可用明细。每行要写成「型号 | 描述 | 数量 | 单价」，数量和单价必须是数字。' if rows.empty?

    pi = build(customer, rows, currency, remark)
    "已建 PI 草稿 #{pi.pi_no}（#{rows.size} 项，合计 #{money(pi.total_amount_micros, pi.currency)}）。" \
      '**状态是草稿、没有发给客户**，请到「PI 形式发票」里核对价格和条款，确认后再导出发送。'
  end

  private

  # 「型号 | 描述 | 数量 | 单价」一行一项。数量或单价缺了/为零的行直接丢掉，不替它猜。
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

  def build(customer, rows, currency, remark)
    pi = scope.account.crm_pis.new(header_attrs(customer, currency, remark))
    rows.each_with_index { |row, i| pi.pi_items.build(item_attrs(row, i)) }
    pi.total_amount_micros = rows.sum { |r| (r[:qty] * r[:price] * 1_000_000).round }
    pi.save!
    pi
  end

  def header_attrs(customer, currency, remark)
    { crm_customer_id: customer.id, owner_id: scope.user_id, status: 'DRAFT', pi_date: Date.current,
      currency: currency.presence || customer.currency_preference.presence || 'USD',
      buyer_company: customer.name, buyer_email: customer.contact_email,
      attention: customer.primary_contact_name, remark: remark.to_s }
  end

  def item_attrs(row, index)
    { position: index, model: row[:model], description: row[:description],
      quantity: row[:qty], unit_price_micros: (row[:price] * 1_000_000).round,
      amount_micros: (row[:qty] * row[:price] * 1_000_000).round }
  end
end
