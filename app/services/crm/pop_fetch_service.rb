require 'net/pop'

# 业务员邮箱收件（POP3）：适用于服务商关闭了 IMAP、仅放开 POP3 的账户（如部分阿里企业邮）。
# 逻辑与 IMAP 收信一致：拉最近 MAX_PER_RUN 封 → 按 Message-ID 去重 → 落 Crm::Email 收件箱。
# 只读取、绝不删除服务器上的邮件（不调用 delete_all / mail.delete）。认证复用 smtp_password。
class Crm::PopFetchService
  include Crm::EmailIngestion

  MAX_PER_RUN = 50
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
      created = pop.mails.last(MAX_PER_RUN).count { |m| ingest_raw(m.pop, fallback_uid: m.number) }
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
