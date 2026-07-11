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
    accounts.find_by(email_address: @email.from_address.to_s.strip) || accounts.first
  end

  def deliver(mail_account)
    email = @email
    message = Mail.new do
      from    mail_account.email_address
      to      email.to_address
      cc      email.cc_address if email.cc_address.present?
      bcc     email.bcc_address if email.bcc_address.present?
      subject email.subject.presence || '(无主题)'
    end
    if email.body_html.present?
      message.html_part = Mail::Part.new(body: email.body_html, content_type: 'text/html; charset=UTF-8')
      message.text_part = Mail::Part.new(body: email.body.to_s, content_type: 'text/plain; charset=UTF-8')
    else
      message.body = email.body.to_s
      message.charset = 'UTF-8'
    end
    email.files.each do |file|
      message.add_file(filename: file.filename.to_s, content: file.download)
    end
    message.delivery_method(:smtp, smtp_settings(mail_account))
    message.deliver!
  end

  def smtp_settings(mail_account)
    settings = {
      address: mail_account.resolved_host,
      port: mail_account.resolved_port,
      domain: mail_account.email_address.split('@').last
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
