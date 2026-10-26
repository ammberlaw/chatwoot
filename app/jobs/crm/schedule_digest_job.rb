# 每天早上把「今天的日程」推给本人。
#
# 日程表原先**没有任何推送**——没有一个任务扫它。于是它是个「你得先想起来去看它，
# 它才能提醒你」的东西，而人只会主动去看自己信得过的工具。
# 2026-10-26 实查：181 条日程只有 8 条被标记完成过（4.4%），
# 其中 133 条是系统自动塞进去的「回复客户来信」，人手工建的只有 12 条。
#
# 不推逾期：逾期的事放侧栏角标里（schedule_events_controller#pending_count 分开报），
# 每天早上把积压的几十条再念一遍，第三天就没人看了——和 MES 预警从日报改周报一个道理。
class Crm::ScheduleDigestJob < ApplicationJob
  queue_as :scheduled_jobs

  # 一条消息里最多列几件。再多就不是提醒而是报表了，点进日程看更合适。
  MAX_ROWS = 8

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
      rows = pending_today(event, today)
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
  def pending_today(event, today)
    done = event.completed_dates.to_a.map(&:to_s)
    event.occurrences_in(today.beginning_of_day, today.end_of_day)
         .reject { |occ| done.include?(occ[:starts_at].to_date.to_s) }
         .map { |occ| { event: event, at: occ[:starts_at] } }
  end

  KIND_LABEL = {
    'reply_reminder' => '回信', 'opp_follow_up' => '商机跟进', 'follow_up' => '跟进'
  }.freeze

  def digest_text(rows)
    sorted = rows.sort_by { |r| r[:at] }
    lines = sorted.first(MAX_ROWS).map { |r| "· #{time_label(r)}#{r[:event].title}" }
    more = sorted.size > MAX_ROWS ? "\n…另有 #{sorted.size - MAX_ROWS} 件" : ''
    "【今日日程】有 #{sorted.size} 件事：\n#{lines.join("\n")}#{more}"
  end

  # 全天事件不摆时间（摆「00:00」会让人以为是凌晨的事），改摆类型。
  def time_label(row)
    event = row[:event]
    return "#{KIND_LABEL[event.kind] || '全天'}｜" if event.all_day?

    "#{row[:at].in_time_zone.strftime('%H:%M')}｜"
  end
end
