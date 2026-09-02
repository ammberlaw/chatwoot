require 'net/pop'

# 业务员邮箱收件（POP3）：适用于服务商关闭了 IMAP、仅放开 POP3 的账户（如阿里企业邮、切走的腾讯/网易）。
# 逻辑与 IMAP 收信一致：拉最近 MAX_PER_RUN 封 → 按 Message-ID 去重 → 落 Crm::Email 收件箱。
# 只读取、绝不删除服务器上的邮件（不调用 delete_all / mail.delete）。认证复用 smtp_password。
class Crm::PopFetchService
  include Crm::EmailIngestion

  MAX_PER_RUN = 200
  OPEN_TIMEOUT = 15   # 连接建立超时（秒）
  RUN_TIMEOUT = 90    # 单账户单次拉取总超时（秒），防止卡死队列

  def initialize(mail_account:)
    @account = mail_account
  end

  def perform
    return 0 if @account.resolved_pop_host.blank? || @account.smtp_password.blank?

    pop = nil
    Timeout.timeout(RUN_TIMEOUT) do
      pop = connect
      # POP3 无 SINCE 检索：取最新的 MAX_PER_RUN 封，靠 Message-ID 去重避免重复入库。
      created = pop.mails.last(MAX_PER_RUN).count { |m| ingest_pop_mail(m) }
      @account.update_column(:imap_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
      created
    end
  rescue StandardError => e
    Rails.logger.error("[Crm::PopFetch] account=#{@account.id} (#{@account.email_address}) failed: #{e.class}: #{e.message}")
    0
  ensure
    safe_close(pop)
  end

  private

  # 先用 TOP 只取邮件头判重（tiny）：已入库的直接跳过、不下载整封正文。
  # 拉最近 MAX_PER_RUN(200) 封时避免每轮把已收邮件整封重下一遍拖爆 RUN_TIMEOUT（POP3 更慢）。
  # 无 Message-ID / 取头失败时兜底走整封（ingest_raw 内部再按 Message-ID 判重）。
  def ingest_pop_mail(mail)
    mid = safe_message_id(mail)
    return false if mid && duplicate?(mid)

    ingest_raw(mail.pop, fallback_uid: mail.number)
  end

  # 只取邮件头（TOP，不拉正文）解析 Message-ID，清洗后与入库去重键口径一致。
  # 服务器不支持 TOP / 取头异常时当作拿不到（返回 nil），回落走整封取信。
  def safe_message_id(mail)
    inner = mail.header.to_s[/^message-id:\s*<(.+?)>/i, 1]
    inner && Crm::MailCharset.scrub(inner)
  rescue StandardError => e
    Rails.logger.debug { "[Crm::PopFetch] account=#{@account.id} num=#{mail.number} header-peek failed, fallback to full fetch: #{e.message}" }
    nil
  end

  def connect
    pop = Net::POP3.new(@account.resolved_pop_host, @account.resolved_pop_port)
    pop.enable_ssl if @account.imap_ssl?
    pop.open_timeout = OPEN_TIMEOUT
    pop.read_timeout = OPEN_TIMEOUT
    pop.start(@account.email_address, @account.smtp_password)
    pop
  end

  def safe_close(pop)
    pop&.finish
  rescue StandardError
    nil
  end
end
