# 每天早上在「团队沟通」给业务员推一条当天简报：该跟谁、欠什么事、哪儿要出问题。
#
# 这些数字 AI 助手本来就答得出来（my_worklist / quotes），但得人想起来去问——
# 真正需要被提醒的恰恰是忙到忘了问的那天。所以反过来推给他。
#
# 刻意**不调模型**：简报就是几行清单，花钱让模型重写一遍没有任何增量，
# 还得每人跑一次（几十个业务员 × 每天）。取数复用 agent 那套 Scope，口径和他自己问到的一致。
#
# 没内容就不发：每天一条「今天没什么事」的消息，三天后就没人看了。
class Crm::DailyBriefJob < ApplicationJob
  queue_as :scheduled_jobs

  LIST_LIMIT = 5          # 每一块最多列几条，多了就只报总数——简报是提醒，不是报表
  QUOTE_EXPIRING_DAYS = 3 # 报价单还剩几天到期算「该催了」
  RECYCLE_WARN_DAYS = 7   # 距离进公海还剩几天算「该跟了」

  # user_ids 供手动补发/测试（如 Crm::DailyBriefJob.perform_now([5695])）。
  def perform(user_ids = nil)
    Account.where(id: Crm::Customer.distinct.select(:account_id)).find_each do |account|
      brief_for_account(account, user_ids)
    end
  end

  private

  BRIEF_PREFIX = '【今日工作简报】'.freeze

  def brief_for_account(account, user_ids)
    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)
    recipients(account, user_ids).each do |account_user|
      # 同一天只发一条：cron 补偿触发、worker 重启重投、或者手动补发时，
      # 原来会让同一个人收到两条一模一样的简报——这种提醒重复一次就开始没人看了。
      next if sent_today?(account, sender.id, account_user.user_id)

      text = compose(account, account_user)
      notifier.notify(account_user.user_id, text) if text.present?
    end
  end

  def sent_today?(account, sender_id, user_id)
    conversation_ids = account.chat_conversations.where(kind: 'direct')
                              .joins(:participants)
                              .where(chat_participants: { user_id: user_id }).select(:id)
    Chat::Message.where(conversation_id: conversation_ids, sender_id: sender_id)
                 .where('content LIKE ?', "#{BRIEF_PREFIX}%")
                 .exists?(created_at: Time.zone.today.all_day)
  end

  # 只推给自己带客户的角色（业务员/主管）。管理员、人事、财务不需要「今天该跟谁」。
  def recipients(account, user_ids)
    rows = account.account_users.includes(:user).where(crm_role: %w[sales manager])
    user_ids.present? ? rows.where(user_id: user_ids) : rows
  end

  def compose(account, account_user)
    scope = Crm::Agent::Scope.new(account: account, account_user: account_user)
    blocks = [followups(scope), tasks(scope), quote_alerts(scope), recycle_alerts(scope),
              receivables(scope)].compact_blank
    return nil if blocks.empty?

    "#{BRIEF_PREFIX}#{Time.zone.today.strftime('%-m月%-d日')}\n\n#{blocks.join("\n\n")}\n\n" \
      '（想问细节直接找「AI 助手」，它看到的和这条一样。）'
  end

  def followups(scope)
    rows = scope.customers.where(next_follow_up_at: ..Time.current).order(:next_follow_up_at)
    block('该跟进的客户', rows) { |c| "#{c.name}（计划 #{date(c.next_follow_up_at)}，上次跟进 #{date(c.last_follow_up_at)}）" }
  end

  # 待办只看派给自己的：别人的待办不该出现在「我的」简报里。
  def tasks(scope)
    rows = scope.follow_up_tasks.where(assignee_id: scope.user_id).where.not(status: 'DONE')
                .where(due_at: ..Time.current.end_of_day).order(Arel.sql('due_at NULLS LAST'))
    block('到期的待办', rows) { |t| "#{t.title}（到期 #{date(t.due_at)}#{t.crm_customer ? "，#{t.crm_customer.name}" : ''}）" }
  end

  # 报价单过期了客户拿着来下单就得重新核价，所以过期和将到期一起报。
  def quote_alerts(scope)
    rows = scope.quotes.pending.where(valid_until: ..QUOTE_EXPIRING_DAYS.days.from_now.end_of_day)
                .where.not(valid_until: nil).order(:valid_until)
    block('报价单要过期了', rows) { |q| "#{q.quote_no} #{q.crm_customer&.name}（#{validity(q.valid_until)}）" }
  end

  # 客户进公海前最后一次提醒：回收是每天凌晨跑的（Crm::RecycleStaleCustomersJob），
  # 等它跑完人才发现，客户已经在公海里被别人领走了。
  #
  # 口径必须跟回收 job 一字不差，否则预警就是噪音：按客户分组各自的天数算，
  # 沉默与否看 LAST_TOUCH_SQL（跟进/邮件/下单/会话/商机任一有动静都算没沉默，
  # 不是只看 last_follow_up_at——天天发邮件的客户不该被报成「要进公海」），
  # 豁免名单里的人整个跳过。
  def recycle_alerts(scope)
    settings = Crm::PublicPoolSetting.for_account(scope.account)
    return nil if !settings.recycle_enabled? || settings.exempt_user_ids.to_a.include?(scope.user_id)

    rows = recycle_warning_rows(scope, settings)
    block('再不跟就要进公海了', rows) { |c| "#{c.name}（#{c.recycle_hint}）" }
  end

  def recycle_warning_rows(scope, settings)
    base = scope.customers.where(is_in_public_pool: false, account_owner_id: scope.user_id)
    per_group = settings.group_recycle_days
    buckets = per_group.map { |group, days| [base.where(customer_group: group), days] }
    buckets << [default_bucket(base, per_group), settings.stale_days]
    buckets.flat_map { |relation, days| near_cutoff(relation, days, settings) }
           .sort_by { |customer| customer.days_left.to_i }
  end

  # 没配专属天数的分组（含未分组）走全局 stale_days，同回收 job。
  def default_bucket(base, per_group)
    return base if per_group.empty?

    base.where(customer_group: nil).or(base.where.not(customer_group: per_group.keys))
  end

  # 窗口含已经过线的（今晚就会被收走，最该提醒）到还剩 RECYCLE_WARN_DAYS 天的。
  # 顺手把「最后互动」select 出来，算剩余天数不用再查一次。
  def near_cutoff(relation, days, settings)
    touch = Crm::Customer::LAST_TOUCH_SQL
    rows = relation.select("crm_customers.*, (#{touch}) AS last_touch_at")
                   .where("#{touch} <= ?", (days - RECYCLE_WARN_DAYS).days.ago)
    rows = rows.where.not(last_follow_up_at: nil) unless settings.recycle_never_followed?
    rows.to_a.each { |customer| annotate_recycle(customer, days) }
  end

  def annotate_recycle(customer, days)
    touched = customer.last_touch_at&.to_date
    left = touched ? days - (Time.zone.today - touched).to_i : 0
    customer.define_singleton_method(:days_left) { left }
    hint = left.positive? ? "还有 #{left} 天" : '已过回收线，今晚就会进公海'
    customer.define_singleton_method(:recycle_hint) { "最后互动 #{touched || '—'}，#{hint}" }
  end

  def receivables(scope)
    rows = scope.receivables.open.to_a
                .select { |r| r.outstanding_micros.to_i.positive? }
                .sort_by { |r| -r.outstanding_micros.to_i }
    block('还没收完的款', rows) do |r|
      "#{r.receivable_no} #{r.crm_customer&.name}（未收 #{amount(r.outstanding_micros, r.currency)}）"
    end
  end

  # 多于 LIST_LIMIT 条就只列前几条 + 报总数：简报滚三屏没人看。
  def block(title, rows)
    list = rows.is_a?(Array) ? rows : rows.to_a
    return nil if list.empty?

    lines = list.first(LIST_LIMIT).map { |row| "· #{yield(row)}" }
    more = list.size > LIST_LIMIT ? "\n…还有 #{list.size - LIST_LIMIT} 条" : ''
    "#{title}（#{list.size}）：\n#{lines.join("\n")}#{more}"
  end

  def validity(valid_until)
    days = (valid_until.to_date - Time.zone.today).to_i
    return "已过期 #{-days} 天" if days.negative?
    return '今天到期' if days.zero?

    "还有 #{days} 天"
  end

  def date(value) = value&.to_date&.to_s || '从没跟进过'

  def amount(micros, currency)
    return '—' if micros.blank?

    "#{currency} #{ActiveSupport::NumberHelper.number_to_delimited(format('%.2f', micros.to_i / 1e6))}"
  end
end
