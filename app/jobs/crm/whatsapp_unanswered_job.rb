# WhatsApp 待回复提醒：客户在 WhatsApp 上发了消息、我们一直没回的，每天早上给号主推一条。
#
# 为什么要做：邮件来信没回有日程提醒（Crm::EmailIngestion#maybe_create_reply_reminder），
# WhatsApp 这条路上一行都没有。而 WhatsApp 已经是主力渠道——2026-11-06 核实：
# 近一周 1355 条收发、138 个会话，是 9 月底的 7 倍；与此同时 **140 个会话客户发了消息没人回，
# 其中 96 个超过 7 天**，抽样全是聊过几十上百条的在跟客户（群聊 0 个，不是广告骚扰）。
#
# 刻意做成**每天一条汇总**而不是每条消息实时提醒：一周 666 条入站，实时提醒就是刷屏，
# 刷几天之后没人看。真正的问题也不是「晚回了两小时」，是「忘了这个人」——
# 忘掉的东西只有列成一张清单才找得回来。
#
# 只管个人号（Channel::WhatsappWeb）：一个号一个主人，提醒给谁是确定的。
# 官方号那个收件箱挂着 14 个成员，没有「该谁回」的答案，归 Chatwoot 自己的指派机制管。
class Crm::WhatsappUnansweredJob < ApplicationJob
  queue_as :scheduled_jobs

  PREFIX = '【WhatsApp 待回复】'.freeze
  # 晾了这么久才算「没回」。早上 9 点半跑，12 小时意味着昨天晚上 9 点半之前的消息才算——
  # 今早刚进来的不算，别让人一上班就被自己还没来得及看的消息问责。
  STALE_AFTER = 12.hours
  # 一条通知里最多列几个，剩下的报个总数。列太长在团队沟通里是一堵墙，没人读。
  MAX_LISTED = 8

  Waiting = Struct.new(:display_id, :name, :phone, :last_in, :preview, keyword_init: true) do
    def waited_text
      hours = ((Time.current - last_in) / 3600).floor
      hours >= 24 ? "#{(hours / 24).floor} 天" : "#{hours} 小时"
    end
  end

  def perform
    Account.where(id: Inbox.where(channel_type: 'Channel::WhatsappWeb').select(:account_id)).find_each do |account|
      remind_account(account)
    end
  end

  private

  def remind_account(account)
    sender = Crm::SystemUser.for(account)
    notifier = Chat::NotifyService.new(account: account, sender: sender)

    personal_inboxes(account).each do |inbox|
      owner_id = inbox.inbox_members.first&.user_id
      # 没有成员的号没人认领（生产有一个），提醒发不出去，跳过。
      next if owner_id.blank? || sent_today?(account, sender.id, owner_id)

      rows = waiting_in(inbox)
      next if rows.empty?

      notifier.notify(owner_id, compose(inbox, rows), ref: ref_for(rows.first))
    end
  end

  def personal_inboxes(account)
    account.inboxes.where(channel_type: 'Channel::WhatsappWeb').includes(:inbox_members)
  end

  # 这个号下「最后一条是客户发的、且已经晾够久」的会话，等得最久的排前面。
  #
  # 一次查完再在 Ruby 里归并：逐个会话查最后一条消息，138 个会话就是 138 次查询。
  # message_type 0=客户发来 1=我们发出；2 是系统活动消息（加人/转派那些），不算回复。
  def waiting_in(inbox)
    last_times(inbox).filter_map do |conversation_id, (last_in, last_out)|
      next if last_in.blank? || last_in > STALE_AFTER.ago
      next if last_out.present? && last_out > last_in

      build_row(conversation_id, last_in)
    end.sort_by(&:last_in)
  end

  def last_times(inbox)
    # reorder(nil)：Message 自带按时间的默认排序，带进 GROUP BY 查询里 PG 会直接报
    # 「created_at must appear in the GROUP BY clause」。
    Message.where(conversation_id: inbox.conversations.select(:id), message_type: [0, 1])
           .reorder(nil)
           .group(:conversation_id)
           .pluck(Arel.sql('conversation_id, MAX(created_at) FILTER (WHERE message_type = 0), ' \
                           'MAX(created_at) FILTER (WHERE message_type = 1)'))
           .to_h { |id, last_in, last_out| [id, [last_in, last_out]] }
  end

  def build_row(conversation_id, last_in)
    conversation = Conversation.includes(:contact).find_by(id: conversation_id)
    return nil if conversation.nil?

    contact = conversation.contact
    Waiting.new(
      display_id: conversation.display_id, name: contact&.name.presence || contact&.phone_number,
      phone: contact&.phone_number, last_in: last_in,
      preview: conversation.messages.where(message_type: 0).order(:id).last&.content.to_s.squish.truncate(40)
    )
  end

  def compose(inbox, rows)
    listed = rows.first(MAX_LISTED).map do |row|
      "· #{row.name}｜等了 #{row.waited_text}#{row.preview.present? ? "：#{row.preview}" : ''}"
    end
    more = rows.size - listed.size
    [
      "#{PREFIX}#{inbox.name}",
      "#{rows.size} 个客户发了消息还没回，最久的等了 #{rows.first.waited_text}。",
      '',
      *listed,
      (more.positive? ? "（另有 #{more} 个，去 WhatsApp 会话列表里看）" : nil)
    ].compact.join("\n")
  end

  # 卡片指向等得最久的那个会话，点一下直接进去回。
  def ref_for(row)
    { type: 'whatsapp_chat', id: row.display_id, label: 'WhatsApp',
      title: row.name.to_s, subtitle: "已等 #{row.waited_text}" }
  end

  # 一人一天最多一条：这个 job 哪怕被重投也不会连发（口径同 Crm::AgentQualityJob）。
  def sent_today?(account, sender_id, user_id)
    conversation_ids = account.chat_conversations.where(kind: 'direct')
                              .joins(:participants)
                              .where(chat_participants: { user_id: user_id }).select(:id)
    Chat::Message.where(conversation_id: conversation_ids, sender_id: sender_id)
                 .where('content LIKE ?', "#{PREFIX}%")
                 .exists?(created_at: Time.zone.today.all_day)
  end
end
