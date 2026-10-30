# 目标体检：一屏看清「谁没设目标、谁设得低于保本线」。
#
# 2026-10-30 之前这两件事在系统里**看不见**：目标是业务员自己在「我的目标」里填的，
# 填多少没人核、不填也没人知道。当时生产上 11 个业务员，10 月只有 6 个设了目标，
# 11 月和 12 月只有 2 个；有两个人把目标填得比自己薪资表里的底线还低。
# 而考核方案里「目标对齐」那 4 分恰恰是按有没有按时设目标判的——分一直在丢，没人看得到。
class Crm::SalesTargetAudit
  Row = Struct.new(
    :owner_id, :name, :baseline, :months_set, :year_total_micros,
    :current_month_micros, :year_required_micros, :current_month_tracked,
    keyword_init: true
  ) do
    # 本月没设目标。最该催的一件事。看往年时无「本月」可言，不算漏设。
    def missing_current_month? = current_month_tracked && current_month_micros.nil?

    # 当年目标合计够不够保本线×12。够不着多少。
    def shortfall_micros
      return nil if year_required_micros.nil?

      [year_required_micros - year_total_micros, 0].max
    end

    def below_baseline? = shortfall_micros.to_i.positive?
  end

  def initialize(account:, year: nil, today: Time.zone.today)
    @account = account
    @today = today
    @year = (year || today.year).to_i
  end

  def rows
    ids = sales_owner_ids
    baselines = Crm::SalaryBaseline.new(account: @account, today: @today).for_owners(ids)
    names = User.where(id: ids).pluck(:id, :name).to_h
    targets = targets_by_owner(ids)
    ids.map { |id| build_row(id, names[id], baselines[id], targets[id] || []) }
       .sort_by { |r| [r.missing_current_month? ? 0 : 1, r.below_baseline? ? 0 : 1, r.name.to_s] }
  end

  # 挂在离职的人或根本没有负责人头上的目标。生产上真有两条
  # （一条负责人是空的、一条是已离职的陈云钢），不摆出来没人会想起去清。
  def orphans
    @account.crm_sales_targets
            .where(target_month: year_range)
            .where('crm_sales_targets.owner_id IS NULL OR crm_sales_targets.owner_id NOT IN (:ids)',
                   ids: sales_owner_ids.presence || [0])
            .includes(:owner).order(:target_month)
  end

  private

  def year_range = Time.zone.local(@year, 1, 1)...Time.zone.local(@year + 1, 1, 1)

  # 在职业务员＝账号上 CRM 角色还是业务员的人。离职会被摘掉角色，所以这个口径天然排除离职。
  def sales_owner_ids
    @sales_owner_ids ||= @account.account_users.where(crm_role: 'sales').pluck(:user_id)
  end

  def targets_by_owner(ids)
    @account.crm_sales_targets
            .where(owner_id: ids, target_month: year_range)
            .pluck(:owner_id, :target_month, :target_amount_micros)
            .group_by(&:first)
  end

  def build_row(owner_id, name, baseline, target_rows)
    this_year = @year == @today.year
    current = target_rows.find { |(_, m, _)| m.to_date == @today.beginning_of_month }
    Row.new(
      owner_id: owner_id, name: name, baseline: baseline,
      months_set: target_rows.map { |(_, m, _)| m.to_date }.uniq.size,
      year_total_micros: target_rows.sum { |(_, _, amount)| amount.to_i },
      current_month_micros: this_year ? current&.last&.to_i : nil,
      current_month_tracked: this_year,
      year_required_micros: required_for(baseline)
    )
  end

  # 年度要求＝月度保本线 × 12。薪资表录的底线优先（那是管理层定下的数），
  # 没录才退回系统建议值。新人期的人两边都可能是空的——不要求，只在页面上标出来。
  def required_for(baseline)
    monthly = baseline&.recorded_micros.presence || baseline&.suggested_micros
    monthly && (monthly.to_i * 12)
  end
end
