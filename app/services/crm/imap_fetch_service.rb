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

  # 按 Message-ID 把某封邮件的原文重新取回来（附件补收用，见 Crm::MailAttachmentRepair）。
  # 服务器上已删除或超出保留期时返回 nil。
  def self.fetch_raw_by_message_id(mail_account, message_id)
    new(mail_account: mail_account).send(:raw_by_message_id, message_id)
  end

  def perform
    return 0 if @account.resolved_imap_host.blank? || @account.smtp_password.blank?

    imap = nil
    created = 0
    Timeout.timeout(RUN_TIMEOUT) do
      imap = connect
      imap.select('INBOX')
      # 用 UID 检索+取信：网易 Coremail 对「按序号取信」偶发返回不合规响应，会让 net-imap 解析
      # 崩溃并污染整条连接（后续全部 closed stream），一封坏邮件就把整箱后续新邮件堵死。UID 路径
      # 更稳；再逐封兜错——个别仍崩的邮件只记日志跳过并重连，绝不阻塞其余邮件。
      uids = imap.uid_search(['SINCE', since_date]).last(MAX_PER_RUN)
      uids.each do |uid|
        created += 1 if ingest_uid(imap, uid)
      rescue Net::IMAP::Error, IOError, Errno::ECONNRESET, Errno::ETIMEDOUT => e
        imap = handle_fetch_error(imap, uid, e)
      end
      @account.update_column(:imap_synced_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
    created
  rescue StandardError => e
    Rails.logger.error("[Crm::ImapFetch] account=#{@account.id} (#{@account.email_address}) failed: #{e.class}: #{e.message}")
    created
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

  # 按 UID 取一封邮件原文入库；入库逻辑见 Crm::EmailIngestion。返回 true 表示新建了记录。
  # 先取 Message-ID 头判重（tiny），已入库的直接跳过、不下载整封正文：跨境/大邮箱 catch-up 时
  # 避免每轮把最近 MAX_PER_RUN 封整封重下一遍拖爆 RUN_TIMEOUT（Gmail 卡死根因），也省掉所有
  # IMAP 账户每轮重下已收邮件的浪费。无 Message-ID 时兜底走整封（ingest_raw 内部再判重）。
  # 网易对坏邮件可能返回空 RFC822（非崩溃），空内容直接跳过不入库。
  def ingest_uid(imap, uid)
    mid = safe_message_id(imap, uid)
    # 判重带上本邮箱主人：同一封信抄送多人要各存一份（见 Crm::EmailIngestion#duplicate?）。
    return false if mid && duplicate?(mid, @account.owner_id)

    # 整封取信仍失败才抛→外层 reopen（网易坏邮件会污染连接，须换连接续收后面的）。
    raw = imap.uid_fetch(uid, 'RFC822')&.first&.attr&.dig('RFC822')
    return false if raw.blank?

    ingest_raw(raw, fallback_uid: uid)
  end

  # 判重用的 Message-ID 头取信容错：网易对「部分头取信」偶发 FETCH 报错，
  # 别因此丢整封——取头失败就当拿不到 Message-ID（返回 nil），回落走整封 RFC822 取信，
  # 由 ingest_raw 内部再按 Message-ID 判重。整封若也取不到才真跳过。
  def safe_message_id(imap, uid)
    message_id_of(imap, uid)
  rescue Net::IMAP::Error, IOError, Errno::ECONNRESET, Errno::ETIMEDOUT => e
    Rails.logger.debug { "[Crm::ImapFetch] account=#{@account.id} uid=#{uid} header-peek failed, fallback to full fetch: #{e.message}" }
    nil
  end

  # 取信失败分流：「no valid message」= 该 UID 邮件已从服务器删除(网易搜索索引残留)，
  # 连接未损坏——静默跳过、不重连(省掉无谓重连开销与刷屏)。其它错误可能污染连接，须重开。
  def handle_fetch_error(imap, uid, err)
    if err.is_a?(Net::IMAP::NoResponseError) && err.message.to_s.include?('no valid message')
      Rails.logger.debug { "[Crm::ImapFetch] account=#{@account.id} skip uid=#{uid}: removed on server" }
      return imap
    end
    Rails.logger.warn("[Crm::ImapFetch] account=#{@account.id} skip uid=#{uid}: #{err.class}: #{err.message}")
    reopen(imap)
  end

  # 补收附件时回查的扫描上限：HEADER 检索不可用的服务器上，最多往回比对这么多封。
  REPAIR_SCAN_LIMIT = 300

  # 按 Message-ID 在 INBOX 里搜出这封邮件并取回原文。
  def raw_by_message_id(message_id)
    imap = nil
    Timeout.timeout(RUN_TIMEOUT) do
      imap = connect
      imap.select('INBOX')
      uid = imap.uid_search(['HEADER', 'MESSAGE-ID', message_id]).last
      # 网易企业邮不支持按 HEADER 检索（恒返回空，不报错），回落成扫最近若干封逐条比对头。
      uid ||= scan_for_message_id(imap, message_id)
      return nil if uid.nil?

      imap.uid_fetch(uid, 'RFC822')&.first&.attr&.dig('RFC822')
    end
  ensure
    safe_close(imap)
  end

  def scan_for_message_id(imap, message_id)
    imap.uid_search(['ALL']).last(REPAIR_SCAN_LIMIT).reverse.find do |uid|
      message_id_of(imap, uid) == message_id
    rescue Net::IMAP::Error, IOError
      false
    end
  end

  # 只取 Message-ID 头（不拉正文），清洗后与入库去重键（Crm::EmailIngestion#ingest_raw）口径一致。
  def message_id_of(imap, uid)
    hdr = imap.uid_fetch(uid, 'BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)]')&.first&.attr&.values&.find { |v| v.is_a?(String) }
    inner = hdr.to_s[/<(.+?)>/, 1]
    inner && Crm::MailCharset.scrub(inner)
  end

  # 单封邮件把连接搞崩后，关掉重开一条干净连接继续收后面的。
  def reopen(imap)
    safe_close(imap)
    fresh = connect
    fresh.select('INBOX')
    fresh
  end

  def safe_close(imap)
    return if imap.nil?

    imap.logout
    imap.disconnect
  rescue StandardError
    nil
  end
end
