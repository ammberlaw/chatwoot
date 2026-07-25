# 收件入库共享逻辑：把一封原始邮件（RFC822 字符串）落成 Crm::Email 收件箱记录。
# 供 IMAP / POP3 两种收件服务复用；依赖 include 方的实例变量 @account（Crm::MailAccount）。
# 按 Message-ID 去重；发件人 → Contact → Crm::Customer 关联客户；归属该邮箱的 owner；
# 通知类发件人（领英/阿里/谷歌/微信通知）过滤，复用 EmailIntakeService 清单。
module Crm::EmailIngestion
  # 把一封原始邮件入库；返回 true 表示新建了一条收件记录。
  # 重复 / 通知类发件人 / 解析异常均返回 false（跳过）。
  # fallback_uid：无 Message-ID 时用它拼一个稳定去重键。
  def ingest_raw(raw, fallback_uid:)
    return false if raw.blank?

    mail = Mail.read_from_string(raw)
    message_id = mail.message_id.presence || "#{@account.id}-#{fallback_uid}"
    return false if duplicate?(message_id)

    from = Array(mail.from).first.to_s
    return false if notification_sender?(from)

    create_email(mail, message_id, from)
    true
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] account=#{@account.id} uid=#{fallback_uid} skipped: #{e.message}")
    false
  end

  private

  def duplicate?(message_id)
    Crm::Email.exists?(account_id: @account.account_id, message_id: message_id)
  end

  def notification_sender?(from)
    domain = from.split('@').last.to_s.downcase
    Crm::EmailIntakeService::NOTIFICATION_DOMAINS.include?(domain) || domain.end_with?('.linkedin.com')
  end

  def create_email(mail, message_id, from)
    html = truncate_text(html_body(mail))
    email = Crm::Email.create!(inbound_attrs(mail, message_id, from, html))
    rewritten = attach_files(email, mail, html)
    email.update!(body_html: truncate_text(rewritten)) if rewritten != html
    email
  end

  def inbound_attrs(mail, message_id, from, html)
    contact = @account.account.contacts.find_by(email: from.downcase)
    {
      account_id: @account.account_id,
      owner_id: @account.owner_id,
      message_id: message_id,
      folder: 'INBOX',
      is_read: false,
      send_status: 'SENT',
      from_address: from,
      to_address: Array(mail.to).join(', ').presence || @account.email_address,
      cc_address: Array(mail.cc).join(', ').presence,
      subject: mail.subject.presence || '(无主题)',
      email_date: mail.date&.to_time || Time.current,
      body: truncate_text(text_body(mail)),
      body_html: html,
      contact_id: contact&.id,
      crm_customer_id: contact&.crm_customer_id
    }
  end

  def html_body(mail)
    part = mail.html_part
    return decoded(part) if part

    mail.multipart? ? nil : (mail.mime_type == 'text/html' ? decoded(mail) : nil)
  end

  def text_body(mail)
    part = mail.text_part
    return decoded(part) if part

    mail.multipart? ? nil : decoded(mail)
  end

  def decoded(part)
    body = part.decoded
    body.force_encoding(part.charset || 'UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
  rescue StandardError
    part.body.to_s
  end

  # 正文超出 text 列上限（ApplicationRecord::MAX_TEXT_COLUMN_LENGTH）时截断入库，
  # 而非整封丢弃 —— 长 HTML 客户邮件仍要能收进来。
  def truncate_text(str)
    return str if str.nil?

    limit = ApplicationRecord::MAX_TEXT_COLUMN_LENGTH
    return str if str.length <= limit

    "#{str[0, limit - 20]}\n…（内容过长，已截断）"
  end

  # 落附件；内联图片（有 Content-ID 且被正文 cid: 引用）单独打 inline 标记、
  # 并把正文里的 cid: 引用改写成 blob 相对访问路径，使其在阅读区正常显示、不混进附件列表。
  # 返回改写后的正文 HTML（无内联图时原样返回）。
  def attach_files(email, mail, html)
    html = html.to_s
    referenced = html_cid_refs(html)
    collect_parts(mail, referenced).each do |part, cid, inline|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(part.decoded),
        filename: part.filename.presence || (inline ? "image_#{cid}" : 'attachment'),
        content_type: part.mime_type,
        metadata: inline ? { 'inline' => true } : {}
      )
      email.files.attach(blob)
      if inline
        path = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
        html = html.gsub(/cid:#{Regexp.escape(cid)}/i, path)
      end
    rescue StandardError => e
      Rails.logger.warn("[Crm::MailFetch] attach failed email=#{email.id}: #{e.message}")
    end
    html
  end

  # 汇总待落地的部件：先取被正文 cid: 引用的内联部件（不论是否被识别为附件），
  # 再取其余真附件（cid 已被内联收走的排除）。返回 [part, cid, inline] 三元组。
  def collect_parts(mail, referenced)
    inline = mail.all_parts.reject(&:multipart?).filter_map do |p|
      cid = normalize_cid(p.content_id)
      [p, cid, true] if cid && referenced.include?(cid)
    end
    inline_ids = inline.to_set { |part, _cid, _flag| part.object_id }
    attachments = mail.attachments.reject { |a| inline_ids.include?(a.object_id) || inline_ref?(a, referenced) }
    inline + attachments.map { |a| [a, nil, false] }
  end

  # 该部件是否为被正文 cid: 引用的内联部件。
  def inline_ref?(part, referenced)
    cid = normalize_cid(part.content_id)
    cid.present? && referenced.include?(cid)
  end

  # 正文中出现的所有 cid 引用（小写），用于判定某内联部件是否真被正文引用。
  def html_cid_refs(html)
    html.scan(/cid:([^"'\s>)]+)/i).flatten.to_set(&:downcase)
  end

  def normalize_cid(raw)
    raw.to_s.strip.delete('<>').downcase.presence
  end
end
