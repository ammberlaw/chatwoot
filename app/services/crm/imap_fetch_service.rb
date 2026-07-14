require 'net/imap'

# 业务员邮箱收件（IMAP）：连接邮箱账户的 INBOX，拉取新邮件落成 Crm::Email 收件箱记录。
# 对应原 A-CRM(Twenty) 的 imap→crmEmail 桥。按 Message-ID 去重；发件人 → Contact → Crm::Customer 关联客户；
# 归属该邮箱的 owner。通知类发件人（领英/阿里/谷歌/微信通知）过滤，复用 EmailIntakeService 清单。
class Crm::ImapFetchService
  # 首次同步回溯天数 + 单次最多处理的新邮件数（防首拉过大）。
  INITIAL_LOOKBACK_DAYS = 7
  MAX_PER_RUN = 50
  OPEN_TIMEOUT = 15   # 连接建立超时（秒）
  RUN_TIMEOUT = 90    # 单账户单次拉取总超时（秒），防止卡死队列

  def initialize(mail_account:)
    @account = mail_account
  end

  def perform
    return 0 if @account.resolved_imap_host.blank? || @account.smtp_password.blank?

    imap = nil
    Timeout.timeout(RUN_TIMEOUT) do
      imap = connect
      imap.select('INBOX')
      ids = imap.search(['SINCE', since_date]).last(MAX_PER_RUN)
      created = ids.count { |id| ingest(imap, id) }
      @account.update_column(:imap_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      created
    end
  rescue StandardError => e
    Rails.logger.error("[Crm::ImapFetch] account=#{@account.id} (#{@account.email_address}) failed: #{e.class}: #{e.message}")
    0
  ensure
    safe_close(imap)
  end

  private

  def connect
    imap = Net::IMAP.new(@account.resolved_imap_host, port: @account.resolved_imap_port,
                                                      ssl: @account.imap_ssl?, open_timeout: OPEN_TIMEOUT)
    imap.login(@account.email_address, @account.smtp_password)
    imap
  end

  def since_date
    (@account.imap_synced_at&.to_date || INITIAL_LOOKBACK_DAYS.days.ago.to_date)
  end

  # 返回 true 表示新建了一条收件记录。
  def ingest(imap, id)
    raw = imap.fetch(id, 'RFC822')&.first&.attr&.dig('RFC822')
    return false if raw.blank?

    mail = Mail.read_from_string(raw)
    message_id = mail.message_id.presence || "#{@account.id}-#{id}"
    return false if duplicate?(message_id)

    from = Array(mail.from).first.to_s
    return false if notification_sender?(from)

    create_email(mail, message_id, from)
    true
  rescue StandardError => e
    Rails.logger.warn("[Crm::ImapFetch] account=#{@account.id} msg=#{id} skipped: #{e.message}")
    false
  end

  def duplicate?(message_id)
    Crm::Email.exists?(account_id: @account.account_id, message_id: message_id)
  end

  def notification_sender?(from)
    domain = from.split('@').last.to_s.downcase
    Crm::EmailIntakeService::NOTIFICATION_DOMAINS.include?(domain) || domain.end_with?('.linkedin.com')
  end

  def create_email(mail, message_id, from)
    contact = @account.account.contacts.find_by(email: from.downcase)
    email = Crm::Email.create!(
      account_id: @account.account_id,
      owner_id: @account.owner_id,
      message_id: message_id,
      folder: 'INBOX',
      is_read: false,
      send_status: 'SENT',
      from_address: from,
      to_address: Array(mail.to).join(', ').presence || @account.email_address,
      cc_address: Array(mail.cc).join(', ').presence,
      subject: mail.subject.presence || '(无主题)',
      email_date: mail.date&.to_time || Time.current,
      body: text_body(mail),
      body_html: html_body(mail),
      contact_id: contact&.id,
      crm_customer_id: contact&.crm_customer_id
    )
    attach_files(email, mail)
    email
  end

  def html_body(mail)
    part = mail.html_part
    return decoded(part) if part

    mail.multipart? ? nil : (mail.mime_type == 'text/html' ? decoded(mail) : nil)
  end

  def text_body(mail)
    part = mail.text_part
    return decoded(part) if part

    mail.multipart? ? nil : decoded(mail)
  end

  def decoded(part)
    body = part.decoded
    body.force_encoding(part.charset || 'UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
  rescue StandardError
    part.body.to_s
  end

  def attach_files(email, mail)
    mail.attachments.each do |att|
      email.files.attach(io: StringIO.new(att.decoded), filename: att.filename.presence || 'attachment',
                         content_type: att.mime_type)
    rescue StandardError => e
      Rails.logger.warn("[Crm::ImapFetch] attach failed email=#{email.id}: #{e.message}")
    end
  end

  def safe_close(imap)
    return if imap.nil?

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end
end
