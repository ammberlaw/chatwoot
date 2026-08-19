# SMTP 直发（对应 A-CRM send-email 云函数，CRM_SPEC §12.4）。
# 按邮件 owner 的邮箱账户发送（多个时按 from_address 匹配，否则取第一个启用的）；
# 成功回写 SENT/发件箱/已读，失败回写 FAILED + 失败原因。
class Crm::EmailSendService
  def initialize(email:)
    @email = email
  end

  def perform
    account = pick_mail_account
    return fail_with('该负责人未配置启用的发信邮箱账户') if account.nil?
    return fail_with('收件人为空') if @email.to_address.blank?

    deliver(account)
    @email.update!(send_status: 'SENT', folder: 'SENT', is_read: true, send_error: nil,
                   from_address: account.email_address, email_date: Time.current, send_now: false)
  rescue StandardError => e
    fail_with(e.message)
  end

  private

  def pick_mail_account
    accounts = Crm::MailAccount.active.where(account_id: @email.account_id, owner_id: @email.owner_id)
    accounts.find_by(email_address: @email.from_address.to_s.strip) ||
      accounts.find_by(is_default: true) || accounts.first
  end

  def deliver(mail_account)
    email = @email
    # 发件人显示名：owner 设了 CRM 英文名就用「英文名 <邮箱>」，没设则纯邮箱（不塞中文名进外发 From）。
    from_name = email.owner&.crm_name.to_s.strip
    from_value = from_name.present? ? "#{from_name} <#{mail_account.email_address}>" : mail_account.email_address
    message = Mail.new do
      from    from_value
      to      email.to_address
      cc      email.cc_address if email.cc_address.present?
      bcc     email.bcc_address if email.bcc_address.present?
      subject email.subject.presence || '(无主题)'
    end
    apply_body(message)
    attach_files(message)
    message.delivery_method(:smtp, smtp_settings(mail_account))
    message.deliver!
  end

  def attach_files(message)
    @email.files.each { |file| message.add_file(filename: file.filename.to_s, content: file.download) }
  end

  # 写信编辑器的文字颜色/下划线在 markdown 里以 span、u 标记存储（草稿再编辑要保留），
  # 发出的纯文本 part 把标记剥掉，收件人不见到源码。
  TEXT_COLOR_MARKER = %r{<span style=color:#\h{6}>|</span>|</?u>}

  # HTML 邮件走 html/text 双 part（HTML 埋追踪像素）；纯文本邮件直接正文。
  def apply_body(message)
    plain_body = @email.body.to_s.gsub(TEXT_COLOR_MARKER, '')
    if @email.body_html.present?
      message.html_part = Mail::Part.new(body: html_with_tracking_pixel, content_type: 'text/html; charset=UTF-8')
      message.text_part = Mail::Part.new(body: plain_body, content_type: 'text/plain; charset=UTF-8')
    else
      message.body = plain_body
      message.charset = 'UTF-8'
    end
  end

  # 在 HTML 正文末尾埋 1×1 追踪像素；收件人邮件客户端加载它即命中回调，记录打开。
  # 仅在真正发送的 SMTP 副本注入，CRM 内存的 body_html 保持干净（阅读页不会误触发）。
  def html_with_tracking_pixel
    token = @email.ensure_tracking_token!
    base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    pixel = %(<img src="#{base}/crm_email_open/#{token}.png" width="1" height="1" alt="" style="display:none" />)
    "#{@email.body_html}#{pixel}"
  end

  def smtp_settings(mail_account)
    settings = {
      address: mail_account.resolved_host,
      port: mail_account.resolved_port,
      domain: mail_account.email_address.split('@').last,
      # 坏邮箱（授权码失效/服务器不响应）会让 deliver! 无限阻塞：拖垮 Sidekiq 发信队列，
      # 且留下「PENDING 无错」的僵尸草稿（前端表现为卡发送中/退回草稿）。
      # 加连接/读取超时 → 快速失败落 FAILED + 明确错误，不再无声挂死。
      open_timeout: 15,
      read_timeout: 20
    }
    if mail_account.smtp_password.present?
      settings[:user_name] = mail_account.smtp_user.presence || mail_account.email_address
      settings[:password] = mail_account.smtp_password
      settings[:authentication] = :login
    end
    if mail_account.use_ssl?
      settings[:ssl] = true
    else
      settings[:enable_starttls_auto] = true
    end
    settings
  end

  def fail_with(message)
    @email.update!(send_status: 'FAILED', send_error: message, send_now: false)
    nil
  end
end
