# 按保本线给业务员铺月度目标。
#
# 为什么要代填：目标全靠业务员自己去「我的目标」里一个月一个月填，生产上的结果是
# 11 个业务员里 11 月、12 月只有 2 个人填了。铺一次全年，他要往上调随时能改，
# 但「忘了填」这件事不该再让考核分替他背。
#
# 只补**缺的月份**，已有的一律不动——业务员自己定高了的目标不能被一键补推回底线。
class Crm::SalesTargetSeeder
  # 薪资表录的底线 / 系统按有效提成率算的建议值。
  SOURCES = %w[recorded suggested].freeze

  Outcome = Struct.new(:created, :skipped, :blocked, keyword_init: true)

  def initialize(account:, owner_ids:, year:, options: {})
    @account = account
    @owner_ids = owner_ids
    @year = year.to_i
    @source = SOURCES.include?(options[:source].to_s) ? options[:source].to_s : 'recorded'
    @today = options[:today] || Time.zone.today
    @from_month = from_month_for(options[:from_month])
  end

  def call
    baselines = Crm::SalaryBaseline.new(account: @account, today: @today).for_owners(@owner_ids)
    outcome = Outcome.new(created: 0, skipped: 0, blocked: [])
    @owner_ids.each { |id| seed_owner(id, baselines[id], outcome) }
    outcome
  end

  private

  # 默认从当月铺到年底；看往年时从 1 月起。已经过去的月份不补——
  # 给 3 月补一个目标只会把他的历史达成率弄花。
  def from_month_for(given)
    explicit = given.to_i
    return explicit.clamp(1, 12) if explicit.positive?

    @year == @today.year ? @today.month : 1
  end

  def seed_owner(owner_id, baseline, outcome)
    monthly = monthly_amount(baseline)
    if monthly.to_i <= 0
      outcome.blocked << { owner_id: owner_id, reason: block_reason(baseline) }
      return
    end
    (@from_month..12).each { |m| create_or_skip(owner_id, m, monthly, outcome) }
  end

  def monthly_amount(baseline)
    return nil if baseline.nil?

    @source == 'suggested' ? baseline.suggested_micros : baseline.recorded_micros.presence || baseline.suggested_micros
  end

  def block_reason(baseline)
    return '薪资表里没有他的记录' if baseline.nil?
    return "还在新人期（入职 #{baseline.tenure_months} 个月），底线要你逐人定" if baseline.new_hire?

    baseline.blockers.presence&.join('；') || '薪资表里没录底线目标，系统也算不出建议值'
  end

  def create_or_skip(owner_id, month, monthly, outcome)
    target_month = Time.zone.local(@year, month, 1)
    if @account.crm_sales_targets.exists?(owner_id: owner_id, target_month: target_month)
      outcome.skipped += 1
      return
    end
    @account.crm_sales_targets.create!(
      name: "#{@year}-#{format('%02d', month)} 目标",
      target_month: target_month, owner_id: owner_id, target_amount_micros: monthly
    )
    outcome.created += 1
  end
end
