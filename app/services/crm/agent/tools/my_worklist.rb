# 「我现在该干什么」——清单，不是数字。
#
# my_numbers 只告诉你「有 12 个客户该跟进了」，接着人一定会问「哪 12 个」。
# 这个工具就是回答那一句的：给名字、给上次聊到哪天、给金额，照着往下打电话。
class Crm::Agent::Tools::MyWorklist < Crm::Agent::Tools::Base
  description '列出待办清单（不是数字）：该跟进的客户、我的待办任务、在谈商机、未收完的款。按提问人自己的数据权限范围列。'
  param :kind, desc: '要哪一类：followups=该跟进的客户｜tasks=待办任务｜opportunities=在谈商机｜receivables=未收款'
  param :limit, type: 'integer', desc: '最多列几条，默认 15，上限 40', required: false

  OPP_STAGES = { 'NEEDS_CONFIRMED' => '需求确认', 'SAMPLING' => '样品中', 'PENDING_PAYMENT' => '待付款' }.freeze

  def execute(kind:, limit: 15)
    n = [limit.to_i, 40].min
    case kind.to_s.strip
    when 'followups' then followups(n)
    when 'tasks' then tasks(n)
    when 'opportunities' then opportunities(n)
    when 'receivables' then receivables(n)
    else 'kind 只能是 followups / tasks / opportunities / receivables 之一。'
    end
  end

  private

  def followups(limit)
    rows = scope.customers.where(next_follow_up_at: ..Time.current)
                .order(:next_follow_up_at).limit(limit)
    return '没有到期该跟进的客户。' if rows.empty?

    list("该跟进的客户（按计划时间从早到晚，共列 #{rows.size} 个）", rows) do |c|
      "#{c.name}（ID #{c.id}）｜#{c.trade_country.presence || '国家未填'}｜" \
        "计划跟进 #{day(c.next_follow_up_at)}｜上次跟进 #{day(c.last_follow_up_at)}｜" \
        "联系人 #{c.primary_contact_name.presence || '—'} #{c.contact_email}"
    end
  end

  def tasks(limit)
    rows = scope.follow_up_tasks.where.not(status: 'DONE').order(Arel.sql('due_at NULLS LAST')).limit(limit)
    return '没有未完成的跟进任务。' if rows.empty?

    list("待办跟进任务（共列 #{rows.size} 条）", rows) do |t|
      "#{t.title}｜到期 #{day(t.due_at)}｜状态 #{t.status}｜" \
        "客户 #{t.crm_customer&.name || '—'}｜负责人 #{t.assignee&.name || '—'}"
    end
  end

  def opportunities(limit)
    rows = scope.opportunities.open_stages.order(Arel.sql('expected_close_date NULLS LAST')).limit(limit)
    return '没有在谈的商机。' if rows.empty?

    list("在谈商机（共列 #{rows.size} 个）", rows) { |opp| opp_line(opp) }
  end

  def opp_line(opp)
    "#{opp.name}｜客户 #{opp.crm_customer&.name || '—'}｜阶段 #{OPP_STAGES[opp.sales_stage] || opp.sales_stage}｜" \
      "金额 #{money(opp.amount_micros, opp.currency.presence || 'CNY')}｜赢率 #{opp.probability || '—'}%｜" \
      "预计成交 #{day(opp.expected_close_date)}｜下一步 #{clip(opp.next_action, 60).presence || '—'}"
  end

  # 未收款：金额是真实业务数字，不是成本/毛利，业务员本就该知道自己客户欠多少。
  def receivables(limit)
    rows = scope.receivables.open.to_a
                .select { |r| r.outstanding_micros.to_i.positive? }
                .sort_by { |r| -r.outstanding_micros.to_i }.first(limit)
    return '没有未收完的应收。' if rows.empty?

    list("未收款（按未收金额从大到小，共列 #{rows.size} 笔）", rows) { |rec| receivable_line(rec) }
  end

  def receivable_line(rec)
    cur = rec.currency
    "#{rec.receivable_no}｜客户 #{rec.crm_customer&.name || '—'}｜" \
      "应收 #{money(rec.total_amount_micros, cur)}｜" \
      "已收 #{money(rec.received_amount_micros, cur, zero: '0.00')}｜" \
      "未收 #{money(rec.outstanding_micros, cur, zero: '0.00')}"
  end

  def list(header, rows)
    "【#{header}】\n#{rows.map { |row| "— #{yield(row)}" }.join("\n")}"
  end
end
