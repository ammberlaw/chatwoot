# 「系统判定」类指标的建议分。
#
# 这类指标的评分标准写得很死（「每缺漏 1 单扣 1 分」「完整率≥95% 得 5 分」），
# 数据也都在库里，本来就不该靠人一条条数。但**只算真能算的那部分**：
#
#   ✅ 订单与PI录入        —— pi_no 和生产订单关联都在库里，规则可完整复现
#   ⚠️ 客户/商机录入完整度 —— 联系人/邮箱/产品/商机可查，「公司背调」没有对应字段
#   ⚠️ 目标对齐            —— 只有月度目标表，系统里没有「季度分解」「年度目标」这两个东西
#   ❌ 历史成交客户归档    —— 分母是一份人工名单，不在系统里，算不出完成率
#
# 算不了的部分**不猜、不折中、不按比例凑**，在理由里写明「这部分系统判不了」，
# 让主管自己看。一个会悄悄算错的分比没有分更糟——它看着像有依据。
#
# 产出的是**建议分**，不是最终分：和 CRM_SALES 那条公式路径一样，
# 最终分仍由主管手填（见 KpiSheetsController#ai_suggest）。
class Crm::KpiSystemScorer
  # 指标名 → 算法。按名字认，因为方案是人建的、没有稳定的指标编码。
  # 名字对不上就返回 nil，落回 AI 建议那条路，不会把分算错。
  RULES = {
    '订单与PI录入' => :order_pi_entry,
    '客户/商机录入完整度' => :customer_completeness,
    '目标对齐' => :target_alignment
  }.freeze

  def initialize(account:, owner_id:, month:)
    @account = account
    @owner_id = owner_id
    @month = month.beginning_of_month
  end

  # 返回 { score:, reason: }，认不出这个指标就返回 nil。
  def call(item)
    rule = RULES[item.name.to_s.strip]
    return nil if rule.nil?

    weight = item.weight.to_f
    return nil unless weight.positive?

    send(rule, weight)
  end

  private

  def month_range = @month...@month.next_month

  # ── 订单与PI录入：全部合规得满分，每缺漏 1 单扣 1 分，扣完为止 ──
  # 「合规」＝挂了 PI 号、或已转成生产订单（两种都算录全了）。
  def order_pi_entry(weight)
    orders = @account.crm_sales_orders.where(owner_id: @owner_id, order_date: month_range)
    total = orders.count
    return { score: weight, reason: '当月没有新签订单，按满分计' } if total.zero?

    missing = orders.count { |o| o.pi_no.blank? && !production_order?(o) }
    { score: [weight - missing, 0].max.round(1),
      reason: "当月新签 #{total} 单，其中 #{missing} 单既没挂 PI 号也没转生产订单，每缺漏 1 单扣 1 分" }
  end

  def production_order?(order)
    @account.mes_production_orders.exists?(crm_sales_order_id: order.id)
  end

  # ── 客户/商机录入完整度：完整率≥95% 满分；90%~95% 六成；<90% 零分 ──
  # 「完整」按评分标准列的四项里**系统查得到的三项**算：联系人、邮箱、产品。
  # 「公司背调」没有对应字段（只有 website / customer_remark，都不是背调结论），
  # 不拿它们硬凑——理由里说明，让主管自己补这一项。
  COMPLETE_TIERS = [[95, 1.0], [90, 0.6]].freeze

  def customer_completeness(weight)
    customers = @account.crm_customers.where(account_owner_id: @owner_id, created_at: month_range).to_a
    total = customers.size
    return { score: weight, reason: '当月没有新建客户，按满分计' } if total.zero?

    ok = customers.count { |c| complete_customer?(c) }
    pct = (ok * 100.0 / total).round(1)
    ratio = COMPLETE_TIERS.find { |floor, _| pct >= floor }&.last || 0.0
    { score: (weight * ratio).round(1),
      reason: "当月新建 #{total} 个客户，#{ok} 个四项齐全，完整率 #{pct}%。缺的是：#{gaps_text(customers)}。" \
              '（「公司背调」系统里没有对应字段，这一项请人工确认）' }
  end

  # 光说「#{ok} 个齐全」主管不知道该催什么。把每一项各缺多少摆出来——
  # 实测有人 42 个客户里联系人和邮箱都是 100%，卡在商机只建了 6 个，
  # 不摆开的话看到的就只是一个「完整率 9.5%」，不知道问题在哪。
  CHECKS = {
    '联系人' => ->(c, _) { c.primary_contact_name.present? },
    '邮箱' => ->(c, _) { c.contact_email.present? },
    '产品' => ->(c, _) { c.product_group.present? },
    '商机' => ->(c, acc) { acc.crm_opportunities.exists?(crm_customer_id: c.id) }
  }.freeze

  def gaps_text(customers)
    gaps = CHECKS.filter_map do |label, check|
      missing = customers.count { |c| !check.call(c, @account) }
      "#{label}缺 #{missing} 个" if missing.positive?
    end
    gaps.presence&.join('、') || '无'
  end

  def complete_customer?(customer)
    CHECKS.values.all? { |check| check.call(customer, @account) }
  end

  # ── 目标对齐：每月 1 日前设定当月目标（标准里是 1.5 分）──
  # 标准另有「每季度首月 5 日前完成季度分解」和「年度目标已录入并更新」各一项，
  # 但 crm_sales_targets 只有月度一种粒度，系统里根本没有季度/年度目标这个东西，
  # 所以这两项判不了。只给月度那一项的分，剩下的在理由里交代清楚。
  MONTHLY_TARGET_POINTS = 1.5

  def target_alignment(weight)
    target = @account.crm_sales_targets.find_by(owner_id: @owner_id, target_month: @month)
    cap = [MONTHLY_TARGET_POINTS, weight].min
    if target.nil?
      return { score: 0.0,
               reason: "没查到 #{@month.strftime('%-m 月')}的月度目标。" \
                       "（本指标共 #{weight} 分，系统只判得了「月度目标」这 #{cap} 分，" \
                       '季度分解与年度目标系统里没有对应数据，请人工评）' }
    end

    on_time = target.created_at.to_date <= @month
    verdict = on_time ? "在当月 1 日前，得 #{cap} 分" : "晚于当月 1 日，这 #{cap} 分不得分"
    { score: on_time ? cap : 0.0,
      reason: "#{@month.strftime('%-m 月')}目标于 #{target.created_at.to_date} 设定，#{verdict}。" \
              "（本指标共 #{weight} 分，系统只判得了「月度目标」这 #{cap} 分，" \
              '季度分解与年度目标系统里没有对应数据，请人工评）' }
  end
end
