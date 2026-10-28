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
    owner_id = ingest_owner_id(mail)
    return false if duplicate?(message_id, owner_id)

    from = Crm::MailCharset.scrub(Array(mail.from).first.to_s)
    return false if notification_sender?(from)
    return false if blocked_sender?(from, mail, owner_id)

    create_email(mail, message_id, from, owner_id)
    true
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] account=#{@account.id} uid=#{fallback_uid} skipped: #{e.message}")
    false
  end

  private

  # 判重口径：**按人**，不是按公司。
  #
  # 原先是全公司一张表查 Message-ID：一封信谁先抓到就归谁（归属按 To 优先判），
  # 其余被抄送的同事再抓到同一封会被当成重复静默丢掉——线上真发生过，客户发给 Tim、
  # 抄送 Ken，Ken 的邮箱每轮都抓得到却永远入不了库。自己人发出的信反而没事，
  # 因为发件记录的 message_id 是空的、撞不上，于是现象是「只有客户抄送我的信收不到」。
  def duplicate?(message_id, owner_id = nil)
    scope = Crm::Email.where(account_id: @account.account_id, message_id: message_id)
    scope = scope.where(owner_id: owner_id) if owner_id
    scope.exists?
  end

  # 这封信在本次抓取里归谁：
  # 本邮箱地址出现在 To/Cc → 归本邮箱主人（抄送方各自存一份，这是上面那个 bug 的修法）；
  # 都没命中（密送 / 别名 / 转发进来的）→ 沿用按 To/Cc 命中的收件邮箱归属，
  # 避免「全收箱」把全公司邮件挂到抓取者名下。
  def ingest_owner_id(mail)
    return @account.owner_id if addressed_to_self?(mail)

    recipient_owner_id(mail) || @account.owner_id
  end

  def addressed_to_self?(mail)
    self_address = @account.email_address.to_s.downcase
    return false if self_address.blank?

    [*Array(mail.to), *Array(mail.cc)].any? { |addr| address_tokens(addr).include?(self_address) }
  end

  # 黑名单拦截：和上面的 notification_sender? 一个路子——**入库前直接丢弃**，
  # 不是收进来再挪进垃圾箱。收进来就还会占列表、进搜索、喂给 AI 摘要，
  # 等于没屏蔽。规则由人维护（Crm::MailBlocklist），命中就记一笔拦截数，
  # 误伤看得见、随时能删。
  #
  # 一次抓取会连着处理一批信，名单在实例上缓存一次就够（抓取服务是每轮新建的）。
  # owner_id＝这封信归谁（见 ingest_owner_id）。全公司规则对谁都拦，个人规则只拦自己名下的——
  # 同一轮抓取里不同邮件可能归不同的人（抄送各存一份），所以按信逐封判，不能按账号一刀切。
  def blocked_sender?(from, mail, owner_id)
    address = Crm::MailBlocklist.sender_address(from)
    rule = blocklist_rules.find { |r| r.applies_to?(owner_id) && r.matches?(address) }
    return false if rule.nil?

    rule.record_hit!(from, Crm::MailCharset.scrub(mail.subject.to_s))
    Rails.logger.info("[Crm::MailFetch] 黑名单拦截 rule=#{rule.value}(#{rule.scope_label}) from=#{address}")
    true
  end

  def blocklist_rules
    @blocklist_rules ||= Crm::MailBlocklist.where(account_id: @account.account_id).to_a
  end

  def notification_sender?(from)
    domain = from.split('@').last.to_s.downcase
    Crm::EmailIntakeService::NOTIFICATION_DOMAINS.include?(domain) ||
      domain.end_with?('.linkedin.com') ||
      # 小满系统通知（noreply@k.xiaomanmail.com「消息通知」）不是客户来信，别灌收件箱。
      domain.end_with?('.xiaomanmail.com') || domain == 'xiaomanmail.com'
  end

  def create_email(mail, message_id, from, owner_id)
    # 先把内联 base64 图换成附件链接再判断长度：否则一张签名 logo 就能把正文顶到上限被截断。
    # 先剥掉被客户回信引用回来的、我们自己的追踪像素/跳转链接（见 Crm::MailTracking），
    # 否则自己人在 CRM 里读这封回信就会被记成「客户又打开了一次」。
    html, inline_blobs = Crm::MailInlineImages.extract(Crm::MailTracking.strip_own(html_body(mail)))
    html = truncate_text(html)
    email = Crm::Email.create!(inbound_attrs(mail, message_id, from, html, owner_id))
    inline_blobs.each { |blob| email.files.attach(blob) }
    rewritten = attach_files(email, mail, html)
    email.update!(body_html: truncate_text(rewritten)) if rewritten != html
    maybe_create_reply_reminder(email)
    enqueue_mail_push(email)
    enqueue_ai_followups(email)
    email
  end

  # 新信推手机。异步、失败不影响收信——收不到推送是小事，收不到信是大事。
  def enqueue_mail_push(email)
    Crm::MailPushJob.perform_later(email.id)
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] enqueue mail push failed email=#{email.id}: #{e.message}")
  end

  # 收信后的 AI 自动化（异步、失败不影响收信）：
  # ① 已建档客户的来信——附件归档到客户档案 + 从往来识别商机进度写跟进记录；
  # ② 没建档的来信——很可能是新询盘，走初筛（背调/建档/起草回复，见 Crm::InquiryTriageJob）。
  # 两条正好互补，一封信只会走其中一条。
  def enqueue_ai_followups(email)
    return enqueue_inquiry_triage(email) if email.crm_customer_id.blank?

    Crm::ArchiveEmailAttachmentsJob.perform_later(email.id) if email.files.attached?
    Crm::EmailProgressJob.perform_later(email.id)
    # 老客户来信预写回复草稿（开关默认关，门槛判断全在 job 自己里，见 AutoDraftReplyJob）。
    Crm::AutoDraftReplyJob.perform_later(email.id)
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] enqueue ai followups failed email=#{email.id}: #{e.message}")
  end

  # 初筛要调模型花钱，所以这里只管入队，该不该跑全由 job 自己判（开关、去重、垃圾过滤）——
  # 判断逻辑放一处，手动补跑某封信时走的是同一套门槛。
  def enqueue_inquiry_triage(email)
    Crm::InquiryTriageJob.perform_later(email.id)
  rescue StandardError => e
    Rails.logger.warn("[Crm::MailFetch] enqueue inquiry triage failed email=#{email.id}: #{e.message}")
  end

  # 客户来信自动提醒：为已建档客户的来信在「日程」里放一条当天全天提醒，
  # 直接进日程/首页今日安排。每客户至多一条 kind=reply_reminder（幂等）：来新信只刷新到当天+更新主题，
  # 不重复堆；业务员回信后可在日程里标完成/删除。
  #
  # 提醒归「这封信实际进了谁的邮箱」（email.owner_id），不是客户负责人。
  # 两者可能不是同一个人：客户发到公司总箱 info@，信归总箱主人，而客户挂在某业务员名下。
  # 原来按客户负责人发，结果是：负责人收到「回复客户来信」，却因为邮件可见性根本
  # 打不开也回不了那封信；真正能回的邮箱主人反而没有任何提醒——提醒成了死胡同。
  # （生产实测：邮件 3774 发到陈云钢的 info@ 总箱，提醒却发给了客户负责人余姗姗。）
  def maybe_create_reply_reminder(email)
    return if email.crm_customer_id.blank?

    customer = Crm::Customer.find_by(id: email.crm_customer_id)
    return if customer.blank?

    owner_id = email.owner_id
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

  def inbound_attrs(mail, message_id, from, html, owner_id)
    contact = @account.account.contacts.find_by(email: from.downcase)
    {
      account_id: @account.account_id,
      # 归属见 ingest_owner_id：判重与归属必须用同一个答案，否则抄送方又会被判重丢掉。
      owner_id: owner_id,
      message_id: message_id,
      folder: 'INBOX',
      is_read: false,
      send_status: 'SENT',
      from_address: from,
      to_address: Crm::MailCharset.scrub(Array(mail.to).join(', ').presence || @account.email_address),
      cc_address: Crm::MailCharset.scrub(Array(mail.cc).join(', ').presence),
      subject: Crm::MailCharset.scrub(mail.subject.presence || '(无主题)'),
      email_date: mail.date&.to_time || Time.current,
      # 发件人时区：Date 头带着对方电脑的偏移（+0200/-0400），折成 UTC 就没了。
      # 存成分钟，给「客户当地时间」用——没建档的客户只能靠这个。
      sender_utc_offset_minutes: sender_offset_minutes(mail),
      body: truncate_text(text_body(mail)),
      body_html: html,
      contact_id: contact&.id,
      crm_customer_id: contact&.crm_customer_id
    }
  end

  # Date 头的时区偏移（分钟）。没有 Date 头、或解析不出时区就返回 nil（不猜 0，
  # 0 是真实存在的时区 UTC+0，拿它当「不知道」会把西非/英国冬令时的客户算错）。
  def sender_offset_minutes(mail)
    offset = mail.date&.utc_offset
    return nil if offset.nil?

    (offset / 60).to_i
  end

  # 收件人邮箱主人：按 To（优先）、Cc 顺序，命中某个启用收件邮箱的地址即归其 owner。匹配不到返回 nil。
  def recipient_owner_id(mail)
    map = mailbox_owner_map
    return nil if map.empty?

    [*Array(mail.to), *Array(mail.cc)].each do |addr|
      tokens = address_tokens(addr)
      hit = map.find { |email, _owner| tokens.include?(email) }
      return hit.last if hit
    end
    nil
  end

  # 收件人字段里的邮箱地址 token（小写）。精确匹配而不是子串，
  # 避免 amber@x.com 命中 xamber@x.com / amber@x.com.cn 把来信错归他人。
  def address_tokens(addr)
    a = addr.to_s.downcase
    tokens = a.scan(/[^\s,;<>"']+@[^\s,;<>"']+/)
    tokens.empty? ? [a] : tokens
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

  # 整封 HTML 源码当纯文本发过来的特征。有些表单/通知服务（如 formsubmit.co）
  # 把同一份 HTML 同时塞进 text/plain 和 text/html 两个 part，两边字节完全一样。
  # 只认「开头就是一份 HTML 文档」。不能顺手把「正文里出现 </html>」也算进来：
  # 业务员自己写的纯文本信，引用历史里常夹着一段 HTML，那种是正常正文（实查 59 封）。
  HTML_DOC = %r{\A\s*(<!doctype\s*html|<html[\s>])}i

  def text_body(mail)
    part = mail.text_part
    raw = if part
            decoded(part)
          elsif !mail.multipart?
            decoded(mail)
          end
    # 照收的话 body 里存的就是一串「<!doctype html>…」：列表摘要、AI 摘要/翻译、
    # 阅读区的纯文本兜底全在吃源码（2026-10-26 用户反馈"邮件乱码"）。
    # HTML 那一份照常进 body_html，不受影响。
    raw&.match?(HTML_DOC) ? html_to_text(raw) : raw
  end

  # 块级标签先换成换行再去标签——直接 full_sanitizer 会把整张表压成一长行。
  def html_to_text(html)
    text = html.gsub(%r{<head\b[^>]*>.*?</head>}mi, ' ')
               .gsub(%r{<(script|style)\b[^>]*>.*?</\1>}mi, ' ')
               .gsub(%r{</(tr|p|div|h[1-6]|li|table)>}i, "\n")
               .gsub(%r{<br\s*/?>}i, "\n")
               .gsub(%r{</t[dh]>}i, ' ')
    ActionView::Base.full_sanitizer.sanitize(text).to_s
                    .gsub(/[ \t]+/, ' ').split("\n").map(&:strip).join("\n")
                    .gsub(/\n{3,}/, "\n\n").strip
  end

  # 字符集处理拆在 Crm::MailCharset（GBK 中文邮件兼容，别再 force_encoding 二次错解）。
  def decoded(part)
    Crm::MailCharset.decoded(part)
  end

  # 正文超出邮件正文上限（Crm::Email::BODY_MAX_LENGTH，与模型校验同值）时截断入库，
  # 而非整封丢弃 —— 长 HTML 客户邮件仍要能收进来。别用全局 20000 text 上限（会腰斩长邮件）。
  def truncate_text(str)
    return str if str.nil?

    limit = Crm::Email::BODY_MAX_LENGTH
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
      blob = upload_blob(
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
      # 附件没落成功 = 用户看到一封「没有附件」的邮件且毫无提示，必须能事后查到并补收：
      # 用 rake crm:repair_attachments[邮件id] 按 Message-ID 回服务器重取。
      Rails.logger.error(
        "[Crm::MailFetch] attach failed email=#{email.id} file=#{part.filename.inspect}: #{e.class}: #{e.message}"
      )
    end
    html
  end

  # 对象存储偶发抖动（生产见过腾讯 COS 返回 The Signature you specified is invalid）
  # 会让附件整个丢掉，重试两次再放弃。
  UPLOAD_RETRIES = 2

  def upload_blob(io:, filename:, content_type:, metadata:)
    attempts = 0
    begin
      ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: content_type, metadata: metadata)
    rescue StandardError
      attempts += 1
      raise if attempts > UPLOAD_RETRIES

      sleep(0.5 * attempts)
      io.rewind
      retry
    end
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
