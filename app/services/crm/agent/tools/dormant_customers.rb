# 「哪些客户快睡着了」——多久没联系、该捞回来的。
#
# 用户原话：「我预警流失的客户是多少?」「我90天预警流失的客户是多少?」——2026-10-24
# 连问两次，agent 两次都答「系统里算不出」。数据其实一直都在，只是没有工具去取。
#
# 🔴 口径（用户 2026-10-27 定的 A 方案）：**只算有过往来的客户**。
# 库里 13142 个客户里有 12152 个既没有跟进记录、也没有一封往来邮件——那是小满迁进来的
# 存量名单，不是「流失」。全算上的话这个数字会被它们淹掉，没人会看第二眼。
#
# 「最近一次接触」取各路之最晚：跟进记录 / 往来邮件 / 下单 / PI / 已发生的日程 / 商机推进。
# 只看跟进记录会把「天天邮件来往、只是没人去点跟进按钮」的客户误报成沉睡；
# 只看跟进+邮件则会把「不走邮件、上周刚下过单」的客户照样报成沉睡（2026-10-31 补齐其余四路，
# 与客户列表「最近联系」、公海回收共用的 Crm::Customer::LAST_TOUCH_SQL 同口径）。
class Crm::Agent::Tools::DormantCustomers < Crm::Agent::Tools::Base
  description '找出多久没联系的客户（沉睡/流失预警）。按提问人自己的数据权限范围算。' \
              '只统计有过往来的客户——从没联系过的存量名单不算沉睡。'
  param :days, type: 'integer', desc: '多少天没联系算沉睡，默认 90', required: false
  param :limit, type: 'integer', desc: '最多列几个，默认 15，上限 40', required: false

  DEFAULT_DAYS = 90
  MAX_LIMIT = 40

  def execute(days: DEFAULT_DAYS, limit: 15)
    n_days = days.to_i.positive? ? days.to_i : DEFAULT_DAYS
    rows = dormant_rows(n_days)
    return "没有超过 #{n_days} 天没联系的客户（只算有过往来的）。" if rows.empty?

    listed = rows.first([limit.to_i, MAX_LIMIT].min.clamp(1, MAX_LIMIT))
    render(n_days, rows.size, listed)
  end

  private

  def render(n_days, total, listed)
    header = "超过 #{n_days} 天没联系的客户：共 #{total} 个，列出 #{listed.size} 个" \
             '（只算有过往来的；每行开头的「ID / 邮箱」就是动手要用的，不必再查一遍）'
    lines = listed.map { |r| "— #{line_for(r)}" }
    "【#{header}】\n#{lines.join("\n")}"
  end

  def line_for(row)
    customer = row[:customer]
    mail = customer.contact_email.presence || '邮箱未填'
    "ID #{customer.id}｜#{mail}｜#{customer.name}｜#{customer.trade_country.presence || '国家未填'}｜" \
      "已 #{row[:days]} 天没联系（最近 #{row[:last_at].to_date}，#{row[:source]}）｜" \
      "状态 #{customer.customer_status.presence || '—'}"
  end

  # { customer:, last_at:, days:, source: } —— 按沉睡天数从多到少。
  def dormant_rows(n_days)
    cutoff = n_days.days.ago
    touches = last_touch_map
    rows = scope.customers.where(id: touches.keys).filter_map do |customer|
      at, source = touches[customer.id]
      next if at.nil? || at > cutoff

      { customer: customer, last_at: at, source: source, days: ((Time.current - at) / 1.day).floor }
    end
    rows.sort_by { |row| -row[:days] }
  end

  # 「最近一次接触」= 六路来源取最晚的那个，并记住是哪一路（答复里要写给人看）。
  # 每张表各自聚合一次再在内存里取大，比逐个客户查六次快几个数量级
  # （库里一万多个客户，逐个查就是八万条 SQL）。
  def last_touch_map
    maps = touch_sources
    ids = maps.flat_map { |_label, m| m.keys }.uniq
    ids.index_with { |id| pick_latest(maps, id) }
  end

  # [[来源名, { 客户id => 时间 }], …]。跟进记录挂在客户表自己身上，其余各查一次聚合。
  def touch_sources
    follow = scope.customers.where.not(last_follow_up_at: nil).pluck(:id, :last_follow_up_at).to_h
    rest = touch_definitions.map { |label, relation, key, time| [label, account_max(relation, key, time)] }
    [['跟进记录', follow]] + rest
  end

  # [来源名, 关系, 客户 id 列, 时间列]。日程只认已发生的，未来的提醒不是「联系过」。
  def touch_definitions
    acc = scope.account
    [
      ['邮件往来', acc.crm_emails.where(folder: %w[INBOX SENT]), :crm_customer_id, :email_date],
      ['下单', acc.crm_sales_orders, :crm_customer_id, :order_date],
      ['PI', acc.crm_pis, :crm_customer_id, :pi_date],
      ['日程', acc.crm_schedule_events.where('starts_at <= ?', Time.current), :customer_id, :starts_at],
      ['商机推进', acc.crm_opportunities, :crm_customer_id, :last_activity_at]
    ]
  end

  def account_max(relation, key_column, time_column)
    relation.where.not(key_column => nil).group(key_column).maximum(time_column)
  end

  # => [时间, 来源]；全空返回 [nil, nil]（调用方据此跳过）。
  def pick_latest(maps, id)
    best = maps.filter_map { |label, m| [m[id].try(:to_time), label] if m[id] }.max_by(&:first)
    best || [nil, nil]
  end
end
