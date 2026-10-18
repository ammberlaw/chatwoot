# 「我这个月做得怎么样」——目标达成、提成、考核三件一起给。
#
# my_numbers 只回答「做了多少」，这里回答的是和目标、和钱挂钩的那部分：
# 离目标还差多少、提成表算出来多少、考核打了多少分、发了没。
#
# 口径刻意分两档：
# · 销售目标跟团队口径（和团队看板一致），团队负责人看得到下属的达成。
# · 提成表和考核表**只给本人**——薪酬数据比业务数据敏感一档。团队负责人要看下属的，
#   去提成表/考核页按原有权限看，不从 AI 这边开口子（那两个页面各有自己的审批链路和可见规则，
#   这里跟着放宽就等于绕过它们）。
class Crm::Agent::Tools::MyTargets < Crm::Agent::Tools::Base
  description '查目标达成和薪酬相关的数字：本月（或指定月）销售目标完成多少、还差多少；我的提成表算出来多少、发放了没；我的绩效考核多少分。问「我离目标还差多少」「这个月提成多少」用这个。'
  param :month, desc: '看哪个月，写成 2026-10 这种；不传按本月', required: false

  KPI_STATUSES = { 'PENDING' => '待填写', 'SUBMITTED' => '已提交待评分', 'SCORED' => '已评分',
                   'HR_CONFIRMED' => '人事已确认', 'ARCHIVED' => '已归档' }.freeze
  SHEET_STATUSES = { 'DRAFT' => '草稿', 'SUBMITTED' => '已提交待审', 'APPROVED' => '主管已通过', 'RETURNED' => '被退回' }.freeze

  def execute(month: nil)
    base = parse_month(month)
    [target_section(base), commission_section(base), kpi_section(base)].join("\n\n")
  end

  private

  def target_section(base)
    actual = actual_amount_micros(base)
    rows = scope.sales_targets.for_month(base).to_a
    head = "【#{month_label(base)}销售目标】"
    return "#{head}这个月没设目标。实际成交 #{money(actual, zero: '0.00')}（折人民币）。" if rows.empty?

    goal = rows.sum { |t| t.target_amount_micros.to_i }
    "#{head}\n#{summary_line(goal, actual)}#{per_owner(rows)}"
  end

  # 达成率和差额都在这儿算完摆出去，不让模型自己做除法（它算错过）。
  def summary_line(goal, actual)
    gap = goal - actual
    pct = goal.positive? ? (actual * 100.0 / goal).round(1) : nil
    text = "目标 #{money(goal, zero: '0.00')}｜实际成交 #{money(actual, zero: '0.00')}（折人民币）"
    text += "｜达成 #{pct}%" if pct
    text + (gap.positive? ? "｜还差 #{money(gap, zero: '0.00')}" : "｜已超额 #{money(-gap, zero: '0.00')}")
  end

  # 团队负责人问这句时，光一个汇总数没用——得知道是谁没跟上。
  def per_owner(rows)
    return '' if rows.size <= 1

    lines = rows.sort_by { |t| -t.target_amount_micros.to_i }.map do |t|
      "— #{t.owner&.name || t.name}｜目标 #{money(t.target_amount_micros, zero: '0.00')}" \
        "#{t.target_order_count.present? ? "｜目标单数 #{t.target_order_count}" : ''}"
    end
    "\n按人分（共 #{rows.size} 条）：\n#{lines.join("\n")}"
  end

  # 成交额口径和 my_numbers、团队看板一字不差（dealt + 折人民币）。三处改口径要一起改。
  def actual_amount_micros(base)
    scope.sales_orders.dealt
         .where(order_date: base.beginning_of_month.beginning_of_day..base.end_of_month.end_of_day)
         .sum(Arel.sql(Crm::SalesOrder::RMB_AMOUNT_MICROS_SQL)).to_i
  end

  def commission_section(base)
    sheet = scope.my_commission_sheets.for_month(base).order(id: :desc).first
    head = "【#{month_label(base)}我的提成表】"
    return "#{head}还没有你这个月的提成表。" if sheet.nil?

    items = sheet.items.to_a
    rates = Crm::CommissionRate.map_for(scope.account)
    "#{head}\n#{commission_body(sheet, items, rates)}#{commission_warnings(items, rates)}"
  end

  # 提成工资复用模型上那套算法（Crm::CommissionItem#commission_salary_micros），
  # 和提成表页、Excel 导出同一个口径——这里绝不另写一份公式。
  def commission_body(sheet, items, rates)
    totals = sheet.totals
    salary = items.sum { |i| i.commission_salary_micros(rates[i.product_category]).to_i }
    ["状态 #{SHEET_STATUSES[sheet.status] || sheet.status}｜明细 #{totals[:count]} 行",
     "销售额RMB #{money(totals[:sales_rmb_micros], zero: '0.00')}｜" \
     "收款额RMB #{money(totals[:received_rmb_micros], zero: '0.00')}",
     "按品类点位算出的提成工资合计 #{money(salary, zero: '0.00')}",
     payout_line(sheet)].join("\n")
  end

  def payout_line(sheet)
    return "财务已发放 #{money(sheet.paid_amount_micros, zero: '0.00')}（#{day(sheet.paid_at)}）" if sheet.paid?

    '财务还没发放。'
  end

  # 两个「提成被静默算成 0」的真实坑，查到就必须报——不报人就拿着少掉一截的数去对账：
  # ① 明细里填的品类名在提成点配置里查无此名 → 点位按 0 算；
  # ② 填了收款额但销售额RMB 空着（美金单最常中招）→ 提成基数算不出来，整行漏掉。
  def commission_warnings(items, rates)
    [unmatched_warning(items, rates), missing_base_warning(items)].compact_blank.join
  end

  def unmatched_warning(items, rates)
    bad = items.filter_map { |i| i.product_category.to_s.strip.presence }.uniq.reject { |c| rates.key?(c) }
    return nil if bad.empty?

    "\n⚠️ 这些品类在提成点配置里查不到，对应行的提成按 0 算了：#{bad.join('、')}。核对一下品类名或补配提成点。"
  end

  def missing_base_warning(items)
    n = items.count { |i| i.received_amount_micros.to_i.positive? && i.sales_rmb_micros.blank? }
    return nil if n.zero?

    "\n⚠️ 有 #{n} 行填了收款额但销售额RMB 是空的，这几行算不出提成（多半是汇率没填）。"
  end

  def kpi_section(base)
    sheet = scope.my_kpi_sheets.for_month(base).order(id: :desc).first
    head = "【#{month_label(base)}我的绩效考核】"
    return "#{head}还没有你这个月的考核表。" if sheet.nil?

    "#{head}\n#{kpi_body(sheet)}"
  end

  def kpi_body(sheet)
    [kpi_head(sheet), kpi_score(sheet), kpi_payout(sheet)].join("\n")
  end

  def kpi_head(sheet)
    scheme = sheet.scheme_name.presence || sheet.scheme&.name || '—'
    "方案 #{scheme}｜状态 #{KPI_STATUSES[sheet.status] || sheet.status}"
  end

  def kpi_score(sheet)
    pass = sheet.pass_score.present? ? "（及格 #{sheet.pass_score}）" : ''
    "总分 #{sheet.total_score&.to_f || '—'}#{pass}｜系数 #{sheet.payout_coefficient&.to_f || '—'}"
  end

  def kpi_payout(sheet)
    paid = sheet.paid_at.present? ? "（已发放 #{day(sheet.paid_at)}）" : ''
    "绩效工资基数 #{money(sheet.performance_base_micros)}｜" \
      "实发绩效 #{money(sheet.actual_payout_micros)}#{paid}"
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
