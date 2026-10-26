# 绩效考核催办：每周一把「等你动手的考核表」摘要推给对应的人。
#
# 为什么要有这个：整条审批链每一步都有即时通知了，但那只在**状态刚变**的那一刻发一次。
# 人当时没点、过两天就忘了，表就一直挂着——2026-10-26 实查：10 张停在「人事已确认、
# 等总经理签」，最久的 18 天；还有一张 7 月的停在「待填报」挂了 81 天。
# 即时通知解决「不知道」，这个任务解决「知道了但忘了」。
#
# 周报不日报：考核是月度节奏，挂两天很正常，天天催只会让人把通知当背景噪音
# （MES 生产预警就是因为这个从日报改的周报）。
class Crm::KpiReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  # 每一步等谁动手。顺序即催办顺序，文案里照这个说。
  STEPS = {
    'PENDING' => '待你填报',
    'SUBMITTED' => '待你打分',
    'SCORED' => '待人事确认',
    'HR_CONFIRMED' => '待你最终确认归档'
  }.freeze

  # 覆盖检查从每月几号开始报。月初几天还在陆续下发，太早报全是假警。
  COVERAGE_CHECK_DAY = 7

  # 「这个人现在有几张考核表该他动」——侧栏角标和每周催办共用这一份判定。
  # 控制器反过来调这里：分家写两份，迟早出现「角标说 3 张、点进去找不到」
  # （MES 那个待办面板就是这么对不上的，2026-10-26 修过一轮）。
  def self.actionable_for(account, account_user)
    return Crm::KpiSheet.none if account_user.blank?

    job = new
    ids = account.crm_kpi_sheets.where(status: STEPS.keys).select do |sheet|
      Array(job.send(:actors_for, account, sheet)).compact.include?(account_user.user_id)
    end.map(&:id)
    account.crm_kpi_sheets.where(id: ids)
  end

  def perform
    Account.where(id: Crm::KpiSheet.distinct.select(:account_id)).find_each do |account|
      remind_pending(account)
      report_coverage_gap(account)
    end
  end

  private

  # ── 催办：按「该谁动」把未完成的表归堆，一人一条摘要 ──────────────
  def remind_pending(account)
    buckets = Hash.new { |h, k| h[k] = [] }
    account.crm_kpi_sheets.where(status: STEPS.keys).includes(:owner).find_each do |sheet|
      Array(actors_for(account, sheet)).compact.uniq.each { |uid| buckets[uid] << sheet }
    end
    return if buckets.empty?

    notifier = Chat::NotifyService.new(account: account, sender: Crm::SystemUser.for(account))
    buckets.each { |user_id, sheets| notifier.notify(user_id, digest_text(sheets, user_id)) }
  end

  # 这张表现在该谁动。主管那一步可能有多个（兼管多部门），其余都是单人。
  def actors_for(account, sheet)
    case sheet.status
    when 'PENDING' then sheet.owner_id
    when 'SUBMITTED' then Org::Department.managers_of(account, sheet.owner_id)
    when 'SCORED' then perf_setting(account).hr_owner_id
    when 'HR_CONFIRMED' then perf_setting(account).gm_owner_id
    end
  end

  # 摘要：几张、分别是谁的、挂了多久。挂最久的排前面——那张最可能被忘了。
  # 收件人就是被考核人本人时说「你的」，不然会读成「Ethan Wu 的…待你填报」（发给 Ethan Wu）。
  def digest_text(sheets, recipient_id)
    rows = sheets.sort_by { |s| -stalled_days(s) }.first(10).map do |s|
      whose = s.owner_id == recipient_id ? '你的' : "#{s.owner&.name} 的"
      "· #{whose}「#{s.scheme_name}」#{STEPS[s.status]}，已等 #{stalled_days(s)} 天"
    end
    more = sheets.size > 10 ? "\n…另有 #{sheets.size - 10} 张" : ''
    "【绩效考核】有 #{sheets.size} 张考核表等你处理：\n#{rows.join("\n")}#{more}"
  end

  # 停留天数按「进入当前状态那一刻」算，不是按建表时间——
  # 按建表算的话，一张走得很顺但月初建的表也会显示「已等 25 天」，催办就失真了。
  ENTERED_AT = {
    'PENDING' => :created_at, 'SUBMITTED' => :employee_signed_at,
    'SCORED' => :manager_signed_at, 'HR_CONFIRMED' => :hr_confirmed_at
  }.freeze

  def stalled_days(sheet)
    at = sheet.public_send(ENTERED_AT.fetch(sheet.status, :created_at)) || sheet.created_at
    (Date.current - at.to_date).to_i
  end

  # ── 覆盖检查：上月有表、这月没有的人，大概率是漏下发了 ────────────
  #
  # 不猜「谁该被考核」：按上月实际下发过的人来比，比按角色猜准得多
  # （离职、转岗、阶段性专项方案都会让「该考核的人」每月不一样）。
  def report_coverage_gap(account)
    return if Date.current.day < COVERAGE_CHECK_DAY

    hr_id = perf_setting(account).hr_owner_id
    return if hr_id.blank?

    missing = missing_owner_ids(account)
    return if missing.empty?

    names = User.where(id: missing).pluck(:name).join('、')
    Chat::NotifyService.new(account: account, sender: Crm::SystemUser.for(account)).notify(
      hr_id,
      "【绩效考核】#{Date.current.strftime('%Y 年 %-m 月')}还有 #{missing.size} 人没下发考核表（上月有）：#{names}。" \
      '确认是不需要考核还是漏了。'
    )
  end

  def missing_owner_ids(account)
    last_month = account.crm_kpi_sheets.for_month(Date.current.prev_month).pluck(:owner_id).uniq
    this_month = account.crm_kpi_sheets.for_month(Date.current).pluck(:owner_id).uniq
    still_active = account.account_users.active_members.pluck(:user_id)
    (last_month - this_month) & still_active
  end

  def perf_setting(account)
    @perf_setting ||= {}
    @perf_setting[account.id] ||= Crm::PerformanceSetting.for_account(account)
  end
end
