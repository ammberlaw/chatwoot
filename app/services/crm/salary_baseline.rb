# 保本业绩线：一个月要做多少销售额，提成刚好覆盖他的月薪。
#
# 口径（2026-10-30 定）：
#   保本月销售额 = 月薪 ÷ 有效提成率
#   有效提成率   = 他自己提成表的 Σ提成工资 ÷ Σ销售额RMB（近 12 个月）
#
# 为什么不拿「品类提成点」直接算：点位是按品类配的（商显工控 2%、平板电脑 1%），
# 卖什么决定保本线差一倍。李银彩 45 单全是平板（1%），保本线 80 万；
# 余珊珊卖商显（2%），同样月薪保本线 44 万。拿任何单一点位算，总有一半人是错的。
# 用他自己提成表算出的有效率，对公除税和运费差额也一并算进去了，
# 且复用 Crm::CommissionItem#commission_salary_micros——提成公式全系统只有那一份。
#
# 只对**入职满 12 个月**的人给建议值。未满一年的新人期要求由管理层逐人定
# （在薪资表手填），这里只标出他还在新人期，不替他猜一个数。
class Crm::SalaryBaseline
  # 入职满这么多个月才按保本线要求。
  REGULAR_TENURE_MONTHS = 12
  # 有效提成率的取样窗口。
  LOOKBACK_MONTHS = 12
  # 建议值向上取整到 5 万——保本线是用来谈的数，不是会计数字，
  # 报一个「44.56 万」没人会照着定目标。
  ROUND_UNIT_MICROS = 50_000 * 1_000_000

  Result = Struct.new(
    :owner_id, :salary_micros, :recorded_micros, :suggested_micros,
    :effective_rate, :tenure_months, :new_hire, :sample, :blockers, :notes,
    keyword_init: true
  ) do
    def new_hire? = new_hire

    # 薪资表录的底线跟建议值差出一截——满一年的人才有意义比。
    def off_by_ratio
      return nil if suggested_micros.to_i.zero? || recorded_micros.to_i.zero?

      (recorded_micros.to_f / suggested_micros).round(2)
    end
  end

  def initialize(account:, today: Time.zone.today)
    @account = account
    @today = today
    @rates = Crm::CommissionRate.map_for(account)
  end

  # { user_id => Result }。一次把全员算完，体检页要逐行摆。
  def for_owners(owner_ids)
    comps = comp_index(owner_ids)
    tenures = tenure_index(owner_ids)
    items = item_index(owner_ids)
    owner_ids.index_with do |id|
      build(id, comps[id], tenures[id], items[id] || [])
    end
  end

  def for_owner(owner_id) = for_owners([owner_id])[owner_id]

  private

  def build(owner_id, comp, tenure, items)
    rate = effective_rate(items)
    salary = comp&.monthly_salary_micros.to_i
    new_hire = tenure.present? && tenure < REGULAR_TENURE_MONTHS
    Result.new(
      owner_id: owner_id, salary_micros: salary,
      recorded_micros: comp&.baseline_target_micros,
      suggested_micros: suggest(salary, rate, new_hire),
      effective_rate: rate, tenure_months: tenure, new_hire: new_hire,
      sample: sample_of(items), blockers: blockers(comp, tenure, rate, items),
      notes: notes(rate, items)
    )
  end

  # 建议值只给「满一年 + 月薪已录 + 算得出有效率」这三样都齐的人。
  def suggest(salary, rate, new_hire)
    return nil if new_hire || salary.zero? || rate.nil? || !rate.positive?

    raw = salary / (rate / 100.0)
    (raw / ROUND_UNIT_MICROS.to_f).ceil * ROUND_UNIT_MICROS
  end

  # 有效提成率（百分数）。点位查不到或销售额RMB 空着的行一律**不参与**，
  # 否则它们会把分母撑大、把率拉低，凭空抬高保本线。
  def effective_rate(items)
    countable = items.select { |i| countable?(i) }
    return nil if countable.empty?

    sales = countable.sum { |i| i.sales_rmb_micros.to_i }
    return nil unless sales.positive?

    commission = countable.sum { |i| i.commission_salary_micros(@rates[i.product_category]).to_i }
    (commission * 100.0 / sales).round(4)
  end

  def countable?(item)
    item.sales_rmb_micros.to_i.positive? && @rates[item.product_category].to_f.positive?
  end

  def sample_of(items)
    countable = items.select { |i| countable?(i) }
    { item_count: countable.size, total_count: items.size,
      sales_micros: countable.sum { |i| i.sales_rmb_micros.to_i },
      categories: countable.map(&:product_category).tally }
  end

  # 算不出来时必须说清缺什么，不然体检页只是一片「—」，没人知道该去补哪。
  def blockers(comp, tenure, rate, items)
    [
      comp.nil? ? '薪资表里没有他的记录' : nil,
      comp && comp.monthly_salary_micros.to_i.zero? ? '薪资表里月薪是空的' : nil,
      tenure.nil? ? 'HR 档案里没有他的入职日期' : nil,
      rate.nil? ? rate_blocker(items) : nil
    ].compact
  end

  # 率算出来了、但有一部分行没算进去——必须报。有人九成销售额落在没配点位的品类上，
  # 率是从剩下一成算的，不说一声就是拿一个看着有依据的数去定别人的目标。
  def notes(rate, items)
    return [] if rate.nil?

    bad = items.reject { |i| countable?(i) }
    return [] if bad.empty?

    bad_sales = bad.sum { |i| i.sales_rmb_micros.to_i }
    total = items.sum { |i| i.sales_rmb_micros.to_i }
    share = total.positive? ? (bad_sales * 100.0 / total).round : 0
    ["另有 #{bad.size} 行没算进来（#{excluded_names(bad)}），占销售额 #{share}%"]
  end

  def excluded_names(bad)
    bad.map { |i| i.product_category.presence || '品类空着' }
       .tally.map { |name, n| "#{name} #{n} 行" }.join('、')
  end

  def rate_blocker(items)
    return '他还没有提成表明细，算不出有效提成率' if items.empty?

    bad = items.reject { |i| countable?(i) }
    "提成明细里这些行取不到点位或销售额RMB 空着，算不出有效提成率：#{excluded_names(bad)}"
  end

  def comp_index(owner_ids)
    @account.crm_employee_comps.where(owner_id: owner_ids)
            .order(:created_at).index_by(&:owner_id)
  end

  # 入职满月数。HR 档案的 user_id 2026-10-30 才按姓名补齐，没档案的返回 nil。
  def tenure_index(owner_ids)
    @account.crm_employees.where(user_id: owner_ids).where.not(hire_date: nil)
            .pluck(:user_id, :hire_date).to_h
            .transform_values { |date| months_between(date, @today) }
  end

  def months_between(from, to)
    ((to.year * 12) + to.month) - ((from.year * 12) + from.month) - (to.day < from.day ? 1 : 0)
  end

  # 近 12 个月的提成明细，按人分组。表的状态不卡（草稿也是他自己录的品类构成，
  # 用来估点位够了）——卡了之后万思思、肖天海这种只有草稿的人一行都取不到。
  def item_index(owner_ids)
    since = @today.beginning_of_month - LOOKBACK_MONTHS.months
    rows = Crm::CommissionItem
           .joins(:sheet).where(account_id: @account.id)
           .where(crm_commission_sheets: { owner_id: owner_ids })
           .where(crm_commission_sheets: { period_month: since.. })
           .select('crm_commission_items.*, crm_commission_sheets.owner_id AS sheet_owner_id')
    rows.group_by { |row| row.sheet_owner_id.to_i }
  end
end
