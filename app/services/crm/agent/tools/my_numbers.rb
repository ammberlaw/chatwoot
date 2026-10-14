# 工作台那几个数字：新增客户、该跟进的、在谈商机、某月成交额、我的待办。
#
# 这几个数原来是旧「AI 助手」意图路由器里写死的分支（ai#ask 的 5 个 metric）。
# 换成 agent 之后那套代码删了，可人照样会问「我这个月做了多少」「还有几个要跟」——
# 所以回到工具里来。口径跟原来一字不差（也和团队看板一致），改口径两边要一起改。
#
# 刻意一次把 5 个数全给出去，不让模型挑 metric：枚举参数它常写错，
# 而这几个数加起来也就几行，一把给完还省一次来回。
class Crm::Agent::Tools::MyNumbers < Crm::Agent::Tools::Base
  description '查工作台数字：近 N 天新增客户数、到了该跟进时间的客户数、在谈商机数与预估金额、某月成交订单笔数与金额、我的待办数。按提问人自己的数据权限范围统计。'
  param :days, type: 'integer', desc: '「新增客户」看最近几天，默认 30', required: false
  param :month, desc: '「成交订单」看哪个月，写成 2026-10 这种；不传按本月', required: false

  def execute(days: 30, month: nil)
    span = days.to_i.clamp(1, 365)
    [new_customers(span), pending_followups, open_opportunities, orders_amount(month), my_tasks].join("\n")
  end

  private

  def new_customers(days)
    n = scope.customers.where(created_at: days.days.ago..).count
    "近 #{days} 天新增客户 #{n} 家。"
  end

  def pending_followups
    n = scope.customers.where(next_follow_up_at: ..Time.current).count
    "有 #{n} 个客户到了该跟进的时间。"
  end

  def open_opportunities
    rows = scope.opportunities.open_stages.to_a
    total = rows.sum { |o| o.amount_cny_micros.to_i }
    "在谈商机 #{rows.size} 个，预估 #{money(total, zero: '0.00')}（按今日牌价折人民币）。"
  end

  def orders_amount(month)
    base = parse_month(month)
    rows = scope.sales_orders.dealt.where(order_date: base.beginning_of_month.beginning_of_day..base.end_of_month.end_of_day)
    total = rows.sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)).to_i
    "#{month_label(base)}成交订单 #{rows.count} 笔，#{money(total, zero: '0.00')}（折人民币）。"
  end

  # 待办只看自己的：别人的待办不是「我的待办」，团队负责人要看全队得用 my_worklist。
  def my_tasks
    n = scope.follow_up_tasks.where(assignee_id: scope.user_id).where.not(status: 'DONE').count
    "你有 #{n} 条待办跟进任务。"
  end

  def parse_month(month)
    Date.strptime(month.to_s, '%Y-%m')
  rescue ArgumentError
    Time.zone.today
  end

  def month_label(base)
    today = Time.zone.today
    base.year == today.year && base.month == today.month ? '本月' : base.strftime('%Y年%-m月')
  end
end
