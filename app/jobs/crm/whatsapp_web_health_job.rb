# 个人 WhatsApp 号掉线巡检。
#
# 为什么要做：个人号掉线的后果比邮箱严重——客户发过来的消息**直接收不到**，而客户那边
# 显示已送达，他以为你在装死。而掉线这件事现在完全没有告警：
# `whatsapp_health_management` 那套只管官方号（进门就 validate_whatsapp_cloud_channel），
# 「我的 WhatsApp」列表虽然会问桥要实况，但必须人工打开那个页面才会触发。
# 2026-11-06 核实生产：5 个号掉线、2 个卡在扫码，胡文宇的号 10-10 就掉了，27 天没人知道。
#
# 两种通知分开，因为该做的事不一样：
#   · 刚掉线（open → 非 open）→ 通知号主，他去重新扫码就行。
#   · 掉了好几天还没人管 → 进管理员的汇总。对号主天天念叨 27 天没有意义，
#     那是管理问题不是提醒问题。
class Crm::WhatsappWebHealthJob < ApplicationJob
  queue_as :scheduled_jobs

  PREFIX = '【WhatsApp 掉线】'.freeze
  STALE_PREFIX = '【WhatsApp 号长期掉线】'.freeze
  BRIDGE_PREFIX = '【WhatsApp 桥接不可达】'.freeze
  # 掉这么久还没恢复就上报管理员。
  STALE_AFTER = 3.days

  def perform
    Account.where(id: Inbox.where(channel_type: 'Channel::WhatsappWeb').select(:account_id)).find_each do |account|
      check_account(account)
    end
  end

  private

  def check_account(account)
    inboxes = account.inboxes.where(channel_type: 'Channel::WhatsappWeb').includes(:inbox_members, :channel).to_a
    return if inboxes.empty?

    live = Whatsapp::BaileysBridgeClient.new.sessions_status
    # 桥接不可达时它返回 {}，这时**一个号都不能判成掉线**——否则一次网络抖动
    # 就给全公司发一轮假警报（界面那边同样的坑，见 WhatsappWebController#live_state）。
    return bridge_unreachable(account, inboxes) if live.blank?

    inboxes.each { |inbox| check_inbox(account, inbox, live[inbox.channel.session_key.to_s] || 'disconnected') }
    report_stale(account, inboxes)
  end

  def check_inbox(account, inbox, actual)
    channel = inbox.channel
    was = channel.connection_status.to_s
    return if was == actual

    # 实况与库里不一致就回写：发送前的校验、绑定页读的都是这一列。
    channel.disconnected_at = actual == 'open' ? nil : Time.current.iso8601
    channel.connection_status = actual
    channel.save!
    # 只有「本来是连着的、现在断了」才叫掉线。从没连上过的（一直停在 qr）不算，
    # 那是还没扫码，通知他「掉线了」只会让人莫名其妙。
    notify_owner(account, inbox, actual) if was == 'open'
  end

  def notify_owner(account, inbox, actual)
    owner_id = inbox.inbox_members.first&.user_id
    return if owner_id.blank?

    text = "#{PREFIX}#{inbox.name}（#{inbox.channel.phone_number.presence || '未记录号码'}）\n" \
           "当前状态：#{status_label(actual)}。掉线期间客户发来的消息收不到，而对方那边显示已送达。\n" \
           '去「邮箱 / WhatsApp 绑定」页重新扫码即可恢复。'
    notifier(account).notify(owner_id, text, ref: binding_ref(inbox))
  end

  # 掉了超过 STALE_AFTER 还没恢复的，每天给管理员一张清单。
  def report_stale(account, inboxes)
    rows = inboxes.filter_map { |inbox| stale_row(inbox) }.sort_by { |r| r[:since] }
    return if rows.empty?

    sender_id = Crm::SystemUser.for(account).id
    text = [
      "#{STALE_PREFIX}#{rows.size} 个号",
      *rows.map { |r| "· #{r[:name]}｜#{status_label(r[:status])} #{r[:days]} 天" },
      '这些号收不到客户消息。要么让本人重新扫码，要么在绑定页解绑。'
    ].join("\n")
    ref = binding_ref(rows.first[:inbox])

    admin_ids(account).each do |user_id|
      next if sent_today?(account, sender_id, user_id, STALE_PREFIX)

      notifier(account).notify(user_id, text, ref: ref)
    end
  end

  def stale_row(inbox)
    channel = inbox.channel
    status = channel.connection_status.to_s
    return nil if status == 'open'

    # disconnected_at 是这个 job 上线后才开始记的，老的掉线记录没有时间，
    # 回落到 channel 最后一次变更时间——它正是上一次状态被回写的时刻。
    since = parse_time(channel.disconnected_at) || channel.updated_at
    return nil if since > STALE_AFTER.ago

    { inbox: inbox, name: inbox.name, status: status, since: since,
      days: ((Time.current - since) / 86_400).floor }
  end

  # 卡片指向「邮箱 / WhatsApp 绑定」页（扫码就在那儿）。那是一个整页、没有单据 id，
  # 带上 inbox id 只是为了让卡片成立，前端路由不读它（同 quote_request 的处理）。
  def binding_ref(inbox)
    { type: 'whatsapp_binding', id: inbox.id, label: 'WhatsApp 绑定',
      title: inbox.name.to_s, subtitle: '去重新扫码' }
  end

  # 桥接本身不可达：告诉管理员，别让号主以为是自己手机的问题。
  def bridge_unreachable(account, inboxes)
    sender_id = Crm::SystemUser.for(account).id
    text = "#{BRIDGE_PREFIX}问不到任何号的在线状态（#{inboxes.size} 个号）。\n" \
           '桥接服务可能挂了或网络不通——这期间所有个人号都收发不了消息。'
    admin_ids(account).each do |user_id|
      next if sent_today?(account, sender_id, user_id, BRIDGE_PREFIX)

      notifier(account).notify(user_id, text)
    end
  end

  STATUS_LABELS = { 'disconnected' => '已掉线', 'qr' => '等待扫码', 'connecting' => '连接中' }.freeze

  def status_label(status) = STATUS_LABELS[status.to_s] || status.to_s

  def parse_time(value)
    value.present? ? Time.zone.parse(value.to_s) : nil
  rescue ArgumentError
    nil
  end

  def notifier(account)
    @notifier ||= {}
    @notifier[account.id] ||= Chat::NotifyService.new(account: account, sender: Crm::SystemUser.for(account))
  end

  def admin_ids(account)
    account.account_users.where(crm_role: 'deputy_admin')
           .or(account.account_users.where(role: :administrator))
           .pluck(:user_id)
  end

  def sent_today?(account, sender_id, user_id, prefix)
    conversation_ids = account.chat_conversations.where(kind: 'direct')
                              .joins(:participants)
                              .where(chat_participants: { user_id: user_id }).select(:id)
    Chat::Message.where(conversation_id: conversation_ids, sender_id: sender_id)
                 .where('content LIKE ?', "#{prefix}%")
                 .exists?(created_at: Time.zone.today.all_day)
  end
end
