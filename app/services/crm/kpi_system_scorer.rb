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
  # 「完整」＝评分标准列的四项全有：公司背调、产品、联系人、邮箱，外加已建商机。
  # 背调原先没有落库（AI 背调是实时查、查完就没了），2026-10-26 起在客户上留痕，
  # 所以只对那天之后建的客户查这一项——历史客户没数据，算他们缺是冤枉。
  COMPLETE_TIERS = [[95, 1.0], [90, 0.6]].freeze

  # 背调留痕是哪天上线的。之前建的客户没这个数据，不能算他们缺。
  BG_TRACKED_SINCE = Time.zone.parse('2026-10-26').freeze

  def customer_completeness(weight)
    customers = @account.crm_customers.where(account_owner_id: @owner_id, created_at: month_range).to_a
    total = customers.size
    return { score: weight, reason: '当月没有新建客户，按满分计' } if total.zero?

    ok = customers.count { |c| complete_customer?(c) }
    pct = (ok * 100.0 / total).round(1)
    ratio = COMPLETE_TIERS.find { |floor, _| pct >= floor }&.last || 0.0
    { score: (weight * ratio).round(1),
      reason: "当月新建 #{total} 个客户，#{ok} 个四项齐全，完整率 #{pct}%。缺的是：#{gaps_text(customers)}。" \
              "#{bg_note}" }
  end

  # 光说「#{ok} 个齐全」主管不知道该催什么。把每一项各缺多少摆出来——
  # 实测有人 42 个客户里联系人和邮箱都是 100%，卡在商机只建了 6 个，
  # 不摆开的话看到的就只是一个「完整率 9.5%」，不知道问题在哪。
  CHECKS = {
    '联系人' => ->(c, _) { c.primary_contact_name.present? },
    '邮箱' => ->(c, _) { c.contact_email.present? },
    '产品' => ->(c, _) { c.product_group.present? },
    '商机' => ->(c, acc) { acc.crm_opportunities.exists?(crm_customer_id: c.id) },
    # 背调从 2026-10-26 才开始留痕（此前 AI 背调是实时查、不落库）。
    # 在那之前建的客户一律不算缺——否则历史客户会把完整率永远压在 0。
    '背调' => ->(c, _) { c.created_at < Crm::KpiSystemScorer::BG_TRACKED_SINCE || c.bg_checked_at.present? }
  }.freeze

  # 背调留痕上线前建的客户不参与这一项，说明一下，免得主管以为漏判了。
  def bg_note
    return '' if @month >= BG_TRACKED_SINCE.to_date.beginning_of_month

    '（当月客户建于背调留痕上线前，这一项未计入）'
  end

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

  # ── 目标对齐：三项各自计分 ──────────────────────────────
  #   月度目标    1.5 分  当月有目标，且当月 1 日前就录好了
  #   季度分解    1.5 分  该季度三个月都有目标，且季度首月 5 日前录完
  #   年度目标    1.0 分  当年 12 个月都有目标
  #
  # 一开始以为要给 crm_sales_targets 加「季度/年度」粒度才算得了，重读标准后发现不用：
  # 「季度目标**分解**」指的就是把季度拆到月，而月就是这张表在存的东西；
  # 「年度目标已录入」同理＝12 个月都录了。实测张欢、Candice 都录满 12 个月，
  # 罗家明只录到 10 月——这个判法分得开，不用动表结构。
  TARGET_PARTS = [
    ['月度目标', 1.5, :monthly_target_ok?],
    ['季度分解', 1.5, :quarter_target_ok?],
    ['年度目标', 1.0, :annual_target_ok?]
  ].freeze

  def target_alignment(weight)
    earned = []
    lost = []
    TARGET_PARTS.each do |label, points, check|
      (send(check) ? earned : lost) << "#{label} #{points} 分"
    end
    score = TARGET_PARTS.sum { |_, points, check| send(check) ? points : 0 }
    { score: [score, weight].min.round(1), reason: target_reason(earned, lost, weight) }
  end

  def target_reason(earned, lost, weight)
    got = earned.presence&.join('、') || '无'
    missed = lost.presence ? "；未达：#{lost.join('、')}" : ''
    base = "得分项：#{got}#{missed}。"
    weight > 4.0 ? "#{base}（本指标共 #{weight} 分，标准只列了 4 分的细则，余量请人工评）" : base
  end

  # 当月目标在当月 1 日前就录好了。晚录＝没按时设定。
  def monthly_target_ok?
    t = targets_this_year.find { |x| x.target_month.to_date == @month.to_date }
    t.present? && t.created_at.to_date <= @month
  end

  # 季度三个月都有目标，且都在季度首月 5 日前录完。
  def quarter_target_ok?
    q_start = Date.new(@month.year, ((@month.month - 1) / 3 * 3) + 1, 1)
    months = (0..2).map { |i| q_start >> i }
    rows = targets_this_year.select { |t| months.include?(t.target_month.to_date) }
    rows.size == 3 && rows.all? { |t| t.created_at.to_date <= q_start + 4 }
  end

  # 当年 12 个月都有目标。
  def annual_target_ok?
    targets_this_year.map { |t| t.target_month.to_date.month }.uniq.size == 12
  end

  def targets_this_year
    @targets_this_year ||= @account.crm_sales_targets
                                   .where(owner_id: @owner_id,
                                          target_month: @month.all_year)
                                   .to_a
  end
end
