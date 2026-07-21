# 邮箱账户连通性检测：实测 SMTP（发信）认证，IMAP（收信）在开启时一并测。
# 返回 { smtp: {ok:, error:}, imap: {ok:, error:} }，供前端在保存后提示授权码是否正确。
class Crm::MailAccountVerifier
  require 'net/smtp'
  require 'net/imap'

  TIMEOUT = 12

  def initialize(account)
    @account = account
  end

  def call
    { smtp: verify_smtp, imap: @account.imap_enabled? ? verify_imap : nil }.compact
  end

  private

  def verify_smtp
    return failure('未填写 SMTP 密码（授权码）') if @account.smtp_password.blank?

    smtp = Net::SMTP.new(@account.resolved_host, @account.resolved_port)
    smtp.open_timeout = TIMEOUT
    smtp.read_timeout = TIMEOUT
    @account.use_ssl? ? smtp.enable_tls : smtp.enable_starttls_auto
    smtp.start(helo_domain, login_user, @account.smtp_password, :login) {}
    { ok: true }
  rescue StandardError => e
    failure(e.message)
  end

  def verify_imap
    imap = Net::IMAP.new(@account.resolved_imap_host, port: @account.resolved_imap_port,
                                                      ssl: @account.imap_ssl?, open_timeout: TIMEOUT)
    imap.login(login_user, @account.smtp_password)
    imap.logout
    { ok: true }
  rescue StandardError => e
    failure(e.message)
  ensure
    imap&.disconnect
  end

  def login_user
    @account.smtp_user.presence || @account.email_address
  end

  def helo_domain
    @account.email_address.to_s.split('@').last.presence || 'localhost'
  end

  def failure(msg)
    { ok: false, error: msg.to_s[0, 200] }
  end
end
