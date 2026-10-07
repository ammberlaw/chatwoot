# 客户互动时间线：把跟进记录、往来邮件、WhatsApp/在线会话、订单合到一条时间轴上。
# 以前客户详情页只看得到手动写的跟进，邮件在邮件中心、聊天在会话里，复盘要开三个页面。
class Crm::CustomerTimeline
  LIMIT_PER_TYPE = 40
  TOTAL_LIMIT = 80

  # mail_owner_ids：调用方按邮件口径算好的可见负责人范围（:all 或 user_id 数组）。
  # 必须传——时间线原来不分归属地列出该客户名下所有邮件的主题和正文摘要，
  # 于是邮件模块特意对某人隐藏的信，从客户详情页这条路又露了出去
  # （生产实测 50 封邮件处于「邮件归属 ≠ 客户负责人」的状态）。
  def initialize(account:, customer:, mail_owner_ids: [])
    @account = account
    @customer = customer
    @mail_owner_ids = mail_owner_ids
  end

  def call
    (notes + emails + conversations + orders)
      .sort_by { |e| e[:at] || Time.zone.at(0) }
      .reverse
      .first(TOTAL_LIMIT)
  end

  private

  def notes
    @account.crm_follow_up_notes.where(crm_customer_id: @customer.id)
            .includes(:owner).order(created_at: :desc).limit(LIMIT_PER_TYPE)
            .map do |n|
      { type: 'note', at: n.created_at, title: n.title, body: n.body,
        who: n.owner&.crm_display_name, tag: n.follow_up_method,
        source: n.source, result_tag: n.result_tag }
    end
  end

  def emails
    scope = @account.crm_emails.where(crm_customer_id: @customer.id)
    scope = scope.where(owner_id: @mail_owner_ids) unless @mail_owner_ids == :all
    # 一封抄送给多位同事的信现在按人各存一份（见 Crm::EmailIngestion#duplicate?）。
    # 时间线是「这个客户来往过什么」，同一封信只该出现一次——按 Message-ID 收敛。
    # 多取一倍再去重，免得去重后凑不满 LIMIT_PER_TYPE 条。
    dedup_by_message_id(scope.order(email_date: :desc).limit(LIMIT_PER_TYPE * 2))
      .map do |e|
      { type: 'email', at: e.email_date || e.created_at, title: e.subject.presence || '(无主题)',
        body: strip_tags(e.body).first(140),
        who: e.folder == 'INBOX' ? e.from_address : e.to_address,
        tag: e.folder == 'INBOX' ? '收到' : '发出', link_id: e.id }
    end
  end

  def dedup_by_message_id(scope)
    scope.to_a.uniq { |e| e.message_id.presence || "id-#{e.id}" }.first(LIMIT_PER_TYPE)
  end

  # 会话按「一次会话一条」记，不是每条消息一条——聊天几十上百条，铺开时间线就没法看了。
  def conversations
    contact_ids = @account.contacts.where(crm_customer_id: @customer.id).pluck(:id)
    return [] if contact_ids.empty?

    @account.conversations.where(contact_id: contact_ids)
            .includes(:inbox).order(last_activity_at: :desc).limit(LIMIT_PER_TYPE)
            .map { |c| conversation_row(c) }
  end

  def conversation_row(conv)
    last = conv.messages.where(message_type: [0, 1]).order(created_at: :desc).first
    { type: 'conversation', at: conv.last_activity_at || conv.created_at,
      title: "#{conv.inbox&.name.presence || '会话'} · #{conv.messages.count} 条消息",
      body: last&.content.to_s.strip.first(140),
      who: conv.assignee&.crm_display_name, tag: channel_label(conv.inbox),
      link_id: conv.display_id }
  end

  # 正文里可能夹着编辑器留下的行内标签，时间线只要文字。
  def strip_tags(text)
    text.to_s.gsub(/<[^>]*>/, ' ').squeeze(' ').strip
  end

  def channel_label(inbox)
    case inbox&.channel_type
    when 'Channel::Whatsapp', 'Channel::WhatsappWeb' then 'WhatsApp'
    when 'Channel::Email' then '邮件'
    when 'Channel::WebWidget' then '网站'
    else inbox&.channel_type.to_s.split('::').last.presence || '会话'
    end
  end

  def orders
    @customer.sales_orders.order(order_date: :desc).limit(LIMIT_PER_TYPE).map do |o|
      { type: 'order', at: o.order_date&.to_time || o.created_at,
        title: "销售订单 #{o.order_no}", body: nil,
        who: o.owner&.crm_display_name, tag: o.status,
        amount: ((o.order_amount_micros || 0) / 1_000_000.0).round(2),
        currency: o.order_currency, link_id: o.id }
    end
  end
end
