# 补回被截断的正文：2026-09-08 之前收信按 20000 字截断（当天起上限已提到 20 万字），
# 被切掉的那段文字找不回来，只能按 Message-ID 回邮箱服务器把原文重新取一遍。
#
# 只重写正文与缺失的内联图；邮件本身的已读状态、客户归属、标签、文件夹、已有附件
# 都保持原样——所以不能靠「删了重收」。新正文不比原来长就不动，避免越修越短。
class Crm::MailBodyRepair
  include Crm::EmailIngestion

  Result = Struct.new(:ok, :reason, :before, :after, :added_files, keyword_init: true)

  def initialize(email:, dry_run: false)
    @email = email
    @dry_run = dry_run
    # @account 是 Crm::EmailIngestion 约定的实例变量（Crm::MailAccount）。
    @account = resolve_account
  end

  def perform
    return fail_with('找不到这封邮件对应的邮箱账户') if @account.nil?
    return fail_with('POP3 收信的邮箱不支持按 Message-ID 回查') if @account.pop3?
    return fail_with('这封邮件没有 Message-ID，无法回查') if @email.message_id.blank?

    raw = Crm::ImapFetchService.fetch_raw_by_message_id(@account, @email.message_id)
    return fail_with('邮箱服务器上已找不到这封邮件（删除或超出保留期）') if raw.blank?

    rebuild(Mail.read_from_string(raw))
  rescue StandardError => e
    fail_with("#{e.class}: #{e.message}")
  end

  private

  def rebuild(mail)
    before = @email.body_html.to_s.length
    return dry_result(before, mail) if @dry_run

    html, inline_blobs = Crm::MailInlineImages.extract(html_body(mail))
    html = truncate_text(html)
    return fail_with("重取到的正文没有更长（#{before} → #{html.length}）") if html.length <= before

    added = write_back(mail, html, inline_blobs)
    Result.new(ok: true, reason: '已补回', before: before, after: @email.body_html.to_s.length, added_files: added)
  end

  # 试运行只报长度，绝不落库也不落对象存储：内联 base64 图按落附件后的链接长度估算，
  # 不调 MailInlineImages.extract（那个会真建 blob，试运行跑一遍就留一地孤儿文件）。
  def dry_result(before, mail)
    html = truncate_text(html_body(mail).to_s.gsub(Crm::MailInlineImages::DATA_URI_RE, 'x' * 80))
    return fail_with("重取到的正文没有更长（#{before} → #{html.length}）") if html.length <= before

    Result.new(ok: true, reason: '试运行，未写库', before: before, after: html.length, added_files: 0)
  end

  # 正文里的 cid: 引用要指向本邮件已有的那张内联图，没有的才新落一份，
  # 否则每修一次就多挂一套重复附件。
  def write_back(mail, html, inline_blobs)
    added = inline_blobs.size
    inline_blobs.each { |blob| @email.files.attach(blob) }
    html, more = relink_inline_parts(mail, html)
    @email.update!(body_html: truncate_text(html), body: truncate_text(text_body(mail)))
    added + more
  end

  def relink_inline_parts(mail, html)
    have = @email.files.index_by { |f| f.filename.to_s }
    added = 0
    collect_parts(mail, html_cid_refs(html)).each do |part, cid, inline|
      next unless inline

      blob = have[part.filename.presence || "image_#{cid}"]&.blob
      added += 1 if blob.nil?
      blob ||= attach_inline(part, cid)
      path = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
      html = html.gsub(/cid:#{Regexp.escape(cid)}/i, path)
    end
    [html, added]
  end

  def attach_inline(part, cid)
    blob = upload_blob(io: StringIO.new(part.decoded),
                       filename: part.filename.presence || "image_#{cid}",
                       content_type: part.mime_type, metadata: { 'inline' => true })
    @email.files.attach(blob)
    blob
  end

  def fail_with(reason)
    Result.new(ok: false, reason: reason, before: @email.body_html.to_s.length, after: nil, added_files: 0)
  end

  # 收这封信的邮箱：优先按归属人下、地址出现在收/抄/发件人里的那个账户（与附件补收同口径）。
  def resolve_account
    addresses = [@email.to_address, @email.cc_address, @email.from_address].join(' ').downcase
    scope = Crm::MailAccount.where(account_id: @email.account_id)
    scope = scope.where(owner_id: @email.owner_id) if @email.owner_id.present?
    scope.detect { |a| addresses.include?(a.email_address.to_s.downcase) } || scope.first
  end
end
