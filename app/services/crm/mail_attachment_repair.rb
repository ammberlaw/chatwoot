# 补收附件：一封已入库的邮件，附件因对象存储/网络抖动没落成功时（收信日志里
# 「attach failed email=xxx」），按 Message-ID 回邮箱服务器把原文取回来，只补缺失的那些。
# 邮件本身不动（正文/已读状态/客户归属都保持原样），所以不能靠删了重收。
class Crm::MailAttachmentRepair
  include Crm::EmailIngestion

  def initialize(email:)
    @email = email
    # @account 是 Crm::EmailIngestion 约定的实例变量（Crm::MailAccount）。
    @account = resolve_account
  end

  def perform
    return { ok: false, reason: '找不到这封邮件对应的邮箱账户' } if @account.nil?
    return { ok: false, reason: 'POP3 收信的邮箱不支持按 Message-ID 回查' } if @account.pop3?
    return { ok: false, reason: '这封邮件没有 Message-ID，无法回查' } if @email.message_id.blank?

    raw = Crm::ImapFetchService.fetch_raw_by_message_id(@account, @email.message_id)
    return { ok: false, reason: '邮箱服务器上已找不到这封邮件（删除或超出保留期）' } if raw.blank?

    { ok: true, added: attach_missing(Mail.read_from_string(raw)) }
  end

  private

  # 只补「当前邮件上没有的文件名」，避免把已收好的附件重复挂一遍。
  def attach_missing(mail)
    have = @email.files.to_set { |f| f.filename.to_s }
    added = 0
    collect_parts(mail, html_cid_refs(@email.body_html.to_s)).each do |part, cid, inline|
      name = part.filename.presence || (inline ? "image_#{cid}" : 'attachment')
      next if have.include?(name)

      @email.files.attach(
        upload_blob(io: StringIO.new(part.decoded), filename: name,
                    content_type: part.mime_type, metadata: inline ? { 'inline' => true } : {})
      )
      added += 1
    end
    added
  end

  # 收这封信的邮箱：优先按归属人下、地址出现在收/抄/发件人里的那个账户。
  def resolve_account
    addresses = [@email.to_address, @email.cc_address, @email.from_address].join(' ').downcase
    scope = Crm::MailAccount.where(account_id: @email.account_id)
    scope = scope.where(owner_id: @email.owner_id) if @email.owner_id.present?
    scope.detect { |a| addresses.include?(a.email_address.to_s.downcase) } || scope.first
  end
end
