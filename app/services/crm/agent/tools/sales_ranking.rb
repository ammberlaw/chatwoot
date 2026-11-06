# 业务员成交排行：谁第一、各自成交多少、我排第几。
#
# 为什么单独开一个工具：my_numbers / my_targets 都只看得到提问人自己权限范围内的数，
# 问「这个月谁是销售冠军」时它手里只有一张个人目标表，答不上来，只能让人自己去看板数
# （2026-10 生产上问过两次，两次都是这个结果）。
#
# 口径与「数据看板 → 团队与客户 → 业务员成交排行」逐字一致：下单日期、排除已取消、
# 按订单金额折人民币、勾了「计入成交排行」的人没出单也以 0 留在榜上。改一边两边都要改。
class Crm::Agent::Tools::SalesRanking < Crm::Agent::Tools::Base
  description '查业务员成交排行：某月或某年谁成交最多、各自多少金额多少笔、提问人自己排第几。' \
              '问「谁是销售冠军」「这个月谁第一」「我排第几」「团队这个月做了多少」用这个。'
  param :period, desc: '看哪个月写 2026-10，看整年写 2026；不传按本月', required: false

  # 排行是全公司口径（和看板一样对全体 CRM 成员开放），但车间、仓管这些没有 CRM 角色的人
  # 本来就进不去数据看板，不能从 AI 这儿绕出一条看全公司业绩的路。
  def execute(period: nil)
    return '成交排行只对 CRM 成员开放，你的账号没有 CRM 角色。' unless scope.account_user&.can_access_crm?

    range, label = parse_period(period)
    rows = ranked_rows(range)
    return "#{label}还没有人出单。" if rows.all? { |r| r[:micros].zero? }

    ([headline(label, rows)] + rows.each_with_index.map { |r, i| row_line(r, i) }).join("\n")
  end

  private

  def headline(label, rows)
    total = rows.sum { |r| r[:micros] }
    orders = rows.sum { |r| r[:orders] }
    "【#{label}业务员成交排行】共 #{orders} 笔，合计 #{money(total, zero: '0.00')}（折人民币，下单日期口径，不含已取消）"
  end

  def row_line(row, index)
    mine = row[:name] == scope.user&.name ? '　← 你' : ''
    "#{index + 1}. #{row[:name]}　#{money(row[:micros], zero: '0.00')}　#{row[:orders]} 笔#{mine}"
  end

  # 有单的按金额聚合，再把勾了「计入成交排行」却没开张的人补成 0 ——
  # 只聚合有单的，没开张的直接从榜上消失，而那几位恰恰最该被看见（口径同 StatsController）。
  def ranked_rows(range)
    orders = scope.account.crm_sales_orders.dealt.where(order_date: range).joins(:owner)
    micros = orders.group('users.name').sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL))
    counts = orders.group('users.name').count
    rows = micros.map { |name, sum| { name: name, micros: sum.to_i, orders: counts[name].to_i } }
    (rows + zero_rows(rows.map { |r| r[:name] })).sort_by { |r| [-r[:micros], r[:name].to_s] }
  end

  def zero_rows(listed)
    scope.account.account_users.active_members.where(in_sales_rank: true).includes(:user)
         .filter_map do |au|
      name = au.user&.name
      { name: name, micros: 0, orders: 0 } if name.present? && listed.exclude?(name)
    end
  end

  # 「2026-10」按月，「2026」按年，写错了按本月。
  def parse_period(period)
    text = period.to_s.strip
    if /\A\d{4}\z/.match?(text)
      year = text.to_i
      [Time.zone.local(year, 1, 1).all_year, "#{year}年"]
    else
      base = month_or_today(text)
      [base.all_month, month_label(base)]
    end
  end

  def month_or_today(text)
    Date.strptime(text, '%Y-%m')
  rescue ArgumentError
    Time.zone.today
  end

  def month_label(base)
    today = Time.zone.today
    base.year == today.year && base.month == today.month ? '本月' : base.strftime('%Y年%-m月')
  end
end
