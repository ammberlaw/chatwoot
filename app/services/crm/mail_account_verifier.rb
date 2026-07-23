# 邮箱账户连通性检测：实测 SMTP（发信）认证，收信（IMAP 或 POP3）在开启时一并测。
# 返回 { smtp: {ok:, error:}, imap: {ok:, error:} }，供前端在保存后提示授权码是否正确。
# 注：收信结果统一放在 imap 键下（前端「收信」提示复用），实际按 receive_protocol 走 IMAP/POP3。
class Crm::MailAccountVerifier
  require 'net/smtp'
  require 'net/imap'
  require 'net/pop'

  TIMEOUT = 12

  def initialize(account)
    @account = account
  end

  def call
    { smtp: verify_smtp, imap: @account.imap_enabled? ? verify_receive : nil }.compact
  end

  private

  def verify_receive
    @account.pop3? ? verify_pop : verify_imap
  end

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
    failure(e.message, :imap)
  ensure
    imap&.disconnect
  end

  def verify_pop
    pop = Net::POP3.new(@account.resolved_pop_host, @account.resolved_pop_port)
    pop.enable_ssl if @account.imap_ssl?
    pop.open_timeout = TIMEOUT
    pop.read_timeout = TIMEOUT
    pop.start(login_user, @account.smtp_password)
    pop.finish
    { ok: true }
  rescue StandardError => e
    failure(e.message, :imap)
  end

  def login_user
    @account.smtp_user.presence || @account.email_address
  end

  def helo_domain
    @account.email_address.to_s.split('@').last.presence || 'localhost'
  end

  def failure(msg, channel = :smtp)
    { ok: false, error: humanize_error(msg.to_s, channel) }
  end

  # 把服务商原始 SMTP/IMAP 报错翻成可操作的中文提示，保留原始错误便于排查。
  # channel: :smtp=发信 / :imap=收信。未命中已知模式时原样返回。
  def humanize_error(raw, channel)
    act = channel == :smtp ? '发信' : '收信'
    hint =
      case raw
      when /system busy/i, /authentication failed/i
        "#{act}认证失败：多为授权码不对，或该账号被邮箱服务商风控限制。请在邮箱后台重新生成「授权码/客户端专用密码」填入；若仍失败，检查该账号是否被限制#{act}。"
      when /LOGIN failed/i
        '收信登录被拒：该账号可能未开启 IMAP（部分阿里企业邮默认关闭），可改用「POP3 收信」，或改用三方客户端安全密码。'
      when /535/, /password/i, /credential/i, /auth/i
        "#{act}认证失败：请确认填的是邮箱「授权码/客户端专用密码」而非登录密码。"
      when /timed out/i, /timeout/i, /ETIMEDOUT/i, /refused/i, /getaddrinfo/i, /Name or service not known/i
        "#{act}连接失败：主机不可达或超时，请检查服务商/主机/端口/网络。"
      end
    hint ? "#{hint}（原始：#{raw[0, 100]}）" : raw[0, 200]
  end
end
