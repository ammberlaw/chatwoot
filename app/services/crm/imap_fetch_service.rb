require 'net/imap'

# 业务员邮箱收件（IMAP）：连接邮箱账户的 INBOX，拉取新邮件落成 Crm::Email 收件箱记录。
# 对应原 A-CRM(Twenty) 的 imap→crmEmail 桥。按 Message-ID 去重；发件人 → Contact → Crm::Customer 关联客户；
# 归属该邮箱的 owner。通知类发件人（领英/阿里/谷歌/微信通知）过滤，复用 EmailIntakeService 清单。
class Crm::ImapFetchService
  include Crm::EmailIngestion

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

  # 取一封邮件原文入库；入库逻辑见 Crm::EmailIngestion。返回 true 表示新建了记录。
  def ingest(imap, id)
    raw = imap.fetch(id, 'RFC822')&.first&.attr&.dig('RFC822')
    ingest_raw(raw, fallback_uid: id)
  end

  def safe_close(imap)
    return if imap.nil?

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end
end
