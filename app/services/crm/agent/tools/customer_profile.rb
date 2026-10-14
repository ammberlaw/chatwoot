# 一个客户的全貌：档案 + 历史订单 + 应收 + 最近互动。
# 「分析客户」问的就是这些，一次给全，省得模型分三次来问。
class Crm::Agent::Tools::CustomerProfile < Crm::Agent::Tools::Base
  description '查看某个客户的完整情况：基本档案、归属业务员、历史成交、最近订单、未收款、最近跟进时间。先用 find_customer 拿到客户ID。'
  param :customer_id, type: 'integer', desc: '客户ID（find_customer 返回的那个）'

  def execute(customer_id:)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户（可能不在你的权限范围内，或者 ID 不对）。" if customer.nil?

    [profile(customer), orders(customer), receivables(customer)].compact.join("\n\n")
  end

  private

  def profile(customer)
    lines = profile_fields(customer).map { |label, value| "#{label} #{val(value)}" }
    "【客户档案】#{customer.name}（ID #{customer.id}）\n#{lines.join('　')}"
  end

  # 用「标签 → 取值」表而不是一长串字符串拼接：字段多，拼接写法读起来全是 presence。
  # 分三段取，单段的取值个数就压下来了。
  def profile_fields(cus)
    identity_fields(cus).merge(contact_fields(cus)).merge(trade_fields(cus))
  end

  def identity_fields(cus)
    { '编码' => cus.customer_code,
      '国家/地区' => [cus.trade_country, cus.trade_city].compact_blank.join(' '),
      '行业' => cus.industry, '来源' => cus.source_channel }
  end

  def contact_fields(cus)
    { "\n联系人" => cus.primary_contact_name, '邮箱' => cus.contact_email,
      '电话' => cus.contact_phone, '网站' => cus.website,
      "\n归属业务员" => cus.account_owner&.name, '等级' => cus.customer_level,
      '状态' => cus.customer_status }
  end

  def trade_fields(cus)
    { "\n累计成交" => "#{cus.deal_order_count.to_i} 单 #{money(cus.deal_total_amount_micros)}",
      '首次成交' => day(cus.first_deal_at), '最近成交' => day(cus.last_deal_at),
      "\n最近跟进" => day(cus.last_follow_up_at), '下次计划跟进' => day(cus.next_follow_up_at),
      "\n备注" => clip(cus.customer_remark, 300) }
  end

  def val(value) = value.presence || '—'

  def orders(customer)
    all = scope.sales_orders.where(crm_customer_id: customer.id)
    rows = all.order(order_date: :desc, id: :desc).limit(8)
    return '【历史订单】还没有订单。' if rows.empty?

    lines = rows.map do |o|
      "#{o.order_no}｜#{day(o.order_date)}｜#{o.name.to_s[0, 40]}｜" \
        "#{money(o.order_amount_micros, o.order_currency.presence || 'CNY')}｜状态 #{o.status}"
    end
    "【最近订单】共 #{all.count} 单，列最近 #{rows.size} 单：\n#{lines.join("\n")}"
  end

  def receivables(customer)
    rows = scope.account.erp_receivables.where(crm_customer_id: customer.id).to_a
    return nil if rows.empty?

    open_rows = rows.reject { |r| r.outstanding_micros.to_i.zero? }
    return "【应收】#{rows.size} 笔已全部收讫。" if open_rows.empty?

    total = open_rows.sum { |r| r.outstanding_micros.to_i }
    "【应收】还有 #{open_rows.size} 笔未收完，未收合计约 #{money(total)}（各笔币种可能不同，仅供参考）。"
  end
end
