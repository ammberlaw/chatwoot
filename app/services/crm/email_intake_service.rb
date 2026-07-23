# 把 Chatwoot 邮件渠道的消息镜像成 CRM 邮件记录（对应 Twenty 的 imap-to-crmemail-bridge 触发器）。
# 方向 incoming→收件箱 / outgoing→发件箱；通知类发件人（领英/阿里/谷歌/微信通知）过滤；
# 按 chatwoot_message_id 去重；send_status 置 SENT 避免触发发信；
# 通过发件人邮箱 → Contact → Crm::Customer 关联客户（Twenty 桥接未做，此处补齐产品语义）。
class Crm::EmailIntakeService
  # 过滤域名清单移植自 Twenty imap-to-crmemail-bridge.sql
  # email.alibaba.com 为阿里「询盘通知」发件域，属平台通知非客户直邮，不入库。
  NOTIFICATION_DOMAINS = %w[linkedin.com mail.linkedin.com accounts.google.com
                            notice.alibaba.com service.alibaba.com email.alibaba.com exmail.weixin.qq.com].freeze

  def initialize(message:)
    @message = message
  end

  def perform
    return unless mirrorable?
    return if already_mirrored?
    return if notification_sender?

    create_crm_email
  end

  private

  attr_reader :message

  def mirrorable?
    message.inbox&.email? && %w[incoming outgoing].include?(message.message_type) && !message.private?
  end

  def already_mirrored?
    Crm::Email.exists?(chatwoot_message_id: message.id)
  end

  def email_data
    @email_data ||= (message.content_attributes[:email] || {}).with_indifferent_access
  end

  # 收件：发件人=对方（邮件头 from，兜底会话联系人）；发件：发件人=本方收件箱邮箱。
  def from_address
    return message.inbox.channel.email unless incoming?

    Array(email_data[:from]).first || message.conversation.contact&.email
  end

  def to_address
    joined = Array(email_data[:to]).join(', ')
    return joined if joined.present?

    incoming? ? message.inbox.channel.email : message.conversation.contact&.email
  end

  def notification_sender?
    domain = from_address.to_s.split('@').last.to_s.downcase
    NOTIFICATION_DOMAINS.include?(domain) || domain.end_with?('.linkedin.com')
  end

  def incoming?
    message.message_type == 'incoming'
  end

  def create_crm_email
    contact = message.conversation.contact
    Crm::Email.create!(
      account_id: message.account_id,
      chatwoot_message_id: message.id,
      subject: email_data[:subject].presence || message.conversation.additional_attributes&.dig('mail_subject').presence || '(无主题)',
      folder: incoming? ? 'INBOX' : 'SENT',
      is_read: !incoming?,
      from_address: from_address,
      to_address: to_address,
      cc_address: Array(email_data[:cc]).join(', ').presence,
      bcc_address: Array(email_data[:bcc]).join(', ').presence,
      email_date: email_data[:date].presence || message.created_at,
      body: email_data.dig(:text_content, :full).presence || message.content,
      body_html: email_data.dig(:html_content, :full).presence,
      send_status: 'SENT',
      contact_id: contact&.id,
      crm_customer_id: contact&.crm_customer_id,
      owner_id: inbox_owner_id
    )
  end

  # 归属：A-CRM 口径「谁连的邮箱，来信归谁」。Chatwoot 收件箱是共享的，
  # 仅当该收件箱只有一个成员时视为个人邮箱、归属该成员。
  def inbox_owner_id
    members = message.inbox.members.limit(2).to_a
    members.one? ? members.first.id : nil
  end
end
