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
    # 邮件头可能带非 UTF-8 原始字节，入库前先清洗——message_id / from 还要先进 PG 查询
    # （去重 / 关联联系人），不清洗会在查询阶段就抛 PG::CharacterNotInRepertoire 丢整封。
    message_id = Crm::MailCharset.scrub(mail.message_id.presence || "#{@account.id}-#{fallback_uid}")
    return false if duplicate?(message_id)

    from = Crm::MailCharset.scrub(Array(mail.from).first.to_s)
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
    Crm::EmailIntakeService::NOTIFICATION_DOMAINS.include?(domain) ||
      domain.end_with?('.linkedin.com') ||
      # 小满系统通知（noreply@k.xiaomanmail.com「消息通知」）不是客户来信，别灌收件箱。
      domain.end_with?('.xiaomanmail.com') || domain == 'xiaomanmail.com'
  end

  def create_email(mail, message_id, from)
    html = truncate_text(html_body(mail))
    email = Crm::Email.create!(inbound_attrs(mail, message_id, from, html))
    rewritten = attach_files(email, mail, html)
    email.update!(body_html: truncate_text(rewritten)) if rewritten != html
    maybe_create_reply_reminder(email)
    enqueue_ai_followups(email)
    email
  end

  # 收信后的 AI 自动化（仅已关联客户的来信；异步、失败不影响收信）：
  # ① 附件自动归档到客户档案；② 从往来识别商机进度写跟进记录。
  def enqueue_ai_followups(email)
    return if email.crm_customer_id.blank?

    Crm::ArchiveEmailAttachmentsJob.perform_later(email.id) if email.files.attached?
    Crm::EmailProgressJob.perform_later(email.id)
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] enqueue ai followups failed email=#{email.id}: #{e.message}")
  end

  # 客户来信自动提醒：为已建档客户的来信在「日程」里放一条当天全天提醒（归客户负责人），
  # 直接进日程/首页今日安排。每客户至多一条 kind=reply_reminder（幂等）：来新信只刷新到当天+更新主题，
  # 不重复堆；业务员回信后可在日程里标完成/删除。
  def maybe_create_reply_reminder(email)
    return if email.crm_customer_id.blank?

    customer = Crm::Customer.find_by(id: email.crm_customer_id)
    owner_id = customer&.account_owner_id
    return if owner_id.blank?

    today = Time.zone.today
    event = @account.account.crm_schedule_events.find_or_initialize_by(customer_id: customer.id, kind: 'reply_reminder')
    event.assign_attributes(
      owner_id: owner_id, title: "回复客户来信：#{email.subject.presence || '(无主题)'}",
      starts_at: today.beginning_of_day, ends_at: today.end_of_day,
      all_day: true, color: 'rose', recurrence: 'none',
      ref_type: 'customer', ref_id: customer.id,
      note: "客户来信待回复 · #{customer.name}"
    )
    event.save!
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] reply reminder failed email=#{email.id}: #{e.message}")
  end

  def inbound_attrs(mail, message_id, from, html)
    contact = @account.account.contacts.find_by(email: from.downcase)
    {
      account_id: @account.account_id,
      # 归属按「这封实际发给谁」定：To/Cc 命中某个收件邮箱 → 归该邮箱主人；匹配不到才回落抓取账户 owner。
      # 避免老板「全收箱」把全公司邮件挂到自己名下、真正收件人因判重看不到自己的信。
      owner_id: recipient_owner_id(mail) || @account.owner_id,
      message_id: message_id,
      folder: 'INBOX',
      is_read: false,
      send_status: 'SENT',
      from_address: from,
      to_address: Crm::MailCharset.scrub(Array(mail.to).join(', ').presence || @account.email_address),
      cc_address: Crm::MailCharset.scrub(Array(mail.cc).join(', ').presence),
      subject: Crm::MailCharset.scrub(mail.subject.presence || '(无主题)'),
      email_date: mail.date&.to_time || Time.current,
      body: truncate_text(text_body(mail)),
      body_html: html,
      contact_id: contact&.id,
      crm_customer_id: contact&.crm_customer_id
    }
  end

  # 收件人邮箱主人：按 To（优先）、Cc 顺序，命中某个启用收件邮箱的地址即归其 owner。匹配不到返回 nil。
  def recipient_owner_id(mail)
    map = mailbox_owner_map
    return nil if map.empty?

    [*Array(mail.to), *Array(mail.cc)].each do |addr|
      a = addr.to_s.downcase
      # 精确匹配收件邮箱 token，避免 amber@x.com 子串命中 xamber@x.com / amber@x.com.cn 把来信错归他人。
      tokens = a.scan(/[^\s,;<>"']+@[^\s,;<>"']+/)
      tokens = [a] if tokens.empty?
      hit = map.find { |email, _owner| tokens.include?(email) }
      return hit.last if hit
    end
    nil
  end

  # {收件邮箱地址(小写) => owner_id}，本次抓取运行内缓存（同一 service 实例处理多封信）。
  def mailbox_owner_map
    @mailbox_owner_map ||= @account.account.crm_mail_accounts
                                   .where(is_active: true).where.not(owner_id: nil)
                                   .pluck(:email_address, :owner_id)
                                   .filter_map { |e, o| [e.to_s.downcase, o] if e.present? }
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

  # 字符集处理拆在 Crm::MailCharset（GBK 中文邮件兼容，别再 force_encoding 二次错解）。
  def decoded(part)
    Crm::MailCharset.decoded(part)
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
  # 再把其余部件分成「嵌入图」(如 Outlook 签名 image00X.png，归内联、不列附件)与「真附件」。
  # 返回 [part, cid, inline] 三元组。
  def collect_parts(mail, referenced)
    inline = referenced_inline_parts(mail, referenced)
    inline_ids = inline.to_set { |part, _cid, _flag| part.object_id }
    rest = mail.attachments.reject { |a| inline_ids.include?(a.object_id) || inline_ref?(a, referenced) }
    embedded, real = rest.partition { |a| embedded_image?(a) }
    inline +
      embedded.map { |a| [a, normalize_cid(a.content_id), true] } +
      real.map { |a| [a, nil, false] }
  end

  # 被正文 cid: 引用的内联部件（不论是否被识别为附件）。
  def referenced_inline_parts(mail, referenced)
    mail.all_parts.reject(&:multipart?).filter_map do |p|
      cid = normalize_cid(p.content_id)
      [p, cid, true] if cid && referenced.include?(cid)
    end
  end

  # 嵌入式装饰图（签名 logo / 社媒图标等）：图片类型 + 非显式 attachment 声明 +
  # (有 Content-ID 或 Outlook 自动命名 imageNNN.ext)。这类图不该占据附件列表，
  # 否则一封长邮件 / 多封往来的签名小图会全堆到底部。用户真正「另存的附件」通常
  # 是 Content-Disposition: attachment，或非图片(PDF/表格/压缩包)，不会被误伤。
  def embedded_image?(part)
    return false unless part.content_type.to_s.downcase.start_with?('image/')
    return false if attachment_disposition?(part)

    normalize_cid(part.content_id).present? ||
      part.filename.to_s.match?(/\Aimage\d+\.(?:png|jpe?g|gif|bmp)\z/i)
  end

  def attachment_disposition?(part)
    part.header[:content_disposition].to_s.downcase.include?('attachment')
  rescue StandardError
    false
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
