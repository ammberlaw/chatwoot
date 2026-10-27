# 每天早上把「今天的日程」推给本人。
#
# 日程表原先**没有任何推送**——没有一个任务扫它。于是它是个「你得先想起来去看它，
# 它才能提醒你」的东西，而人只会主动去看自己信得过的工具。
# 2026-10-26 实查：181 条日程只有 8 条被标记完成过（4.4%），
# 其中 133 条是系统自动塞进去的「回复客户来信」，人手工建的只有 12 条。
#
# 🔴 2026-10-27 改成「今天 + 逾期」。原先只推今天，理由是「每天把积压的几十条再念一遍，
# 第三天就没人看了」——但那建立在「角标可信、逾期的人自己会去看」之上，而事实是：
# 上线两天**一条都没发出去**。184 条日程几乎全是已逾期的，逾期的不在「今天」窗口里，
# 于是每天早上扫一遍、一条也捞不出来，等于没上线。
# 逾期单独成段、标出逾期天数，并和今天的合计限行（MAX_ROWS），不会变成念积压。
class Crm::ScheduleDigestJob < ApplicationJob
  queue_as :scheduled_jobs

  # 一条消息里最多列几件。再多就不是提醒而是报表了，点进日程看更合适。
  MAX_ROWS = 8
  # 逾期往回看多久。与侧栏角标同口径（schedule_events_controller 的 OVERDUE_WINDOW_DAYS），
  # 两边不一致就会出现「角标说 5 件、推送只念 3 件」。
  OVERDUE_WINDOW_DAYS = 30

  def perform
    Account.where(id: Crm::ScheduleEvent.distinct.select(:account_id)).find_each do |account|
      notify_account(account)
    end
  end

  private

  def notify_account(account)
    today = Time.zone.today
    by_owner = Hash.new { |h, k| h[k] = [] }
    account.crm_schedule_events.find_each do |event|
      rows = pending_rows(event, today)
      by_owner[event.owner_id].concat(rows) if rows.any?
    end
    return if by_owner.empty?

    notifier = Chat::NotifyService.new(account: account, sender: Crm::SystemUser.for(account))
    by_owner.each do |owner_id, rows|
      next if owner_id.blank?

      notifier.notify(owner_id, digest_text(rows))
    end
  end

  # 今天这条日程还有没有没做的。全天事件也会落在今天这一格里。
  def pending_rows(event, today)
    pending_in(event, today.beginning_of_day, today.end_of_day, overdue: false) +
      pending_in(event, (today - OVERDUE_WINDOW_DAYS).beginning_of_day, (today - 1).end_of_day, overdue: true)
  end

  def pending_in(event, from, to, overdue:)
    done = event.completed_dates.to_a.map(&:to_s)
    event.occurrences_in(from, to)
         .reject { |occ| done.include?(occ[:starts_at].to_date.to_s) }
         .map { |occ| { event: event, at: occ[:starts_at], overdue: overdue } }
  end

  KIND_LABEL = {
    'reply_reminder' => '回信', 'opp_follow_up' => '商机跟进', 'follow_up' => '跟进'
  }.freeze

  # 逾期的排在前面：拖得越久越该先看见。今天的按时间排。
  def digest_text(rows)
    overdue, today_rows = rows.partition { |r| r[:overdue] }
    sorted = overdue.sort_by { |r| r[:at] } + today_rows.sort_by { |r| r[:at] }
    lines = sorted.first(MAX_ROWS).map { |r| "· #{line_text(r)}" }
    more = sorted.size > MAX_ROWS ? "\n…另有 #{sorted.size - MAX_ROWS} 件" : ''
    "【#{headline(overdue.size, today_rows.size)}】\n#{lines.join("\n")}#{more}"
  end

  def headline(overdue_count, today_count)
    return "今日日程：#{today_count} 件" if overdue_count.zero?
    return "逾期未办：#{overdue_count} 件" if today_count.zero?

    "今天 #{today_count} 件，另有 #{overdue_count} 件逾期"
  end

  def line_text(row)
    return "#{time_label(row)}#{row[:event].title}" unless row[:overdue]

    days = (Time.zone.today - row[:at].to_date).to_i
    "逾期#{days}天｜#{row[:event].title}"
  end

  # 全天事件不摆时间（摆「00:00」会让人以为是凌晨的事），改摆类型。
  def time_label(row)
    event = row[:event]
    return "#{KIND_LABEL[event.kind] || '全天'}｜" if event.all_day?

    "#{row[:at].in_time_zone.strftime('%H:%M')}｜"
  end
end
