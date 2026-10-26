# SMTP 直发（对应 A-CRM send-email 云函数，CRM_SPEC §12.4）。
# 按邮件 owner 的邮箱账户发送（多个时按 from_address 匹配，否则取第一个启用的）；
# 成功回写 SENT/发件箱/已读，失败回写 FAILED + 失败原因。
class Crm::EmailSendService
  def initialize(email:)
    @email = email
  end

  def perform
    account = pick_mail_account
    return fail_with('该负责人未配置启用的发信邮箱账户') if account.nil?
    return fail_with('收件人为空') if @email.to_address.blank?

    deliver(account)
    @email.update!(send_status: 'SENT', folder: 'SENT', is_read: true, send_error: nil,
                   from_address: account.email_address, email_date: Time.current, send_now: false)
    resolve_reply_reminder
  rescue StandardError => e
    fail_with(e.message)
  end

  private

  # 回完信就把日程里那条「回复客户来信」销掉。
  #
  # 这条提醒是客户来信时自动建的（Crm::EmailIngestion#maybe_create_reply_reminder），
  # 但原先只能人工去日程里点完成——于是回了信提醒还挂着。2026-10-26 实查：
  # 133 条回复提醒里 103 条早就回过信了，84 条挂了两周以上，侧栏角标因此只涨不落，
  # 人学会无视它，真正还没回的那 30 条也跟着被埋了。
  #
  # 销掉用的是「标完成」而不是删：日程上留一条划掉的记录，比凭空消失好查。
  # 失败只记日志——信已经发出去了，不能因为销提醒出错把发信判成失败。
  def resolve_reply_reminder
    customer_id = @email.crm_customer_id
    return if customer_id.blank?

    @email.account.crm_schedule_events
          .where(customer_id: customer_id, kind: 'reply_reminder', owner_id: @email.owner_id)
          .find_each { |event| mark_done_today(event) }
  rescue StandardError => e
    Rails.logger.warn("[Crm::EmailSend] 销回复提醒失败 email=#{@email.id}: #{e.message}")
  end

  def mark_done_today(event)
    today = Time.zone.today.to_s
    dates = event.completed_dates.to_a.map(&:to_s)
    return if dates.include?(today)

    event.update_columns(completed_dates: dates + [today], updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def pick_mail_account
    accounts = Crm::MailAccount.active.where(account_id: @email.account_id, owner_id: @email.owner_id)
    accounts.find_by(email_address: @email.from_address.to_s.strip) ||
      accounts.find_by(is_default: true) || accounts.first
  end

  def deliver(mail_account)
    email = @email
    # 发件人显示名：owner 设了 CRM 英文名就用「英文名 <邮箱>」，没设则纯邮箱（不塞中文名进外发 From）。
    from_name = email.owner&.crm_name.to_s.strip
    from_value = from_name.present? ? "#{from_name} <#{mail_account.email_address}>" : mail_account.email_address
    message = Mail.new do
      from    from_value
      to      email.to_address
      cc      email.cc_address if email.cc_address.present?
      bcc     email.bcc_address if email.bcc_address.present?
      subject email.subject.presence || '(无主题)'
    end
    apply_body(message, @email.files.attached?)
    attach_files(message)
    message.delivery_method(:smtp, smtp_settings(mail_account))
    message.deliver!
  end

  def attach_files(message)
    @email.files.each { |file| message.add_file(filename: file.filename.to_s, content: file.download) }
  end

  # 写信编辑器的文字颜色/下划线在 markdown 里以 span、u 标记存储（草稿再编辑要保留），
  # 发出的纯文本 part 把标记剥掉，收件人不见到源码。
  TEXT_COLOR_MARKER = %r{<span style=color:#\h{6}>|</span>|</?u>}

  # HTML 邮件走 html/text 双 part（HTML 埋追踪像素）；纯文本邮件直接正文。
  # ⚠ 有附件时必须显式把 html/text 包进一层 multipart/alternative：否则 Mail 会把附件
  # 直接并入顶层 multipart/alternative，收件端把附件当成"正文的备选格式"忽略——
  # 表现为"正文收到、附件不见"。包一层后顶层随附件成为 multipart/mixed，附件正常显示。
  # 纯文本 part 里的 markdown 图片语法：收件人切到纯文本视图会看到 `![](一长串链接)`。
  MD_IMAGE = /!\[[^\]]*\]\([^)\s]*\)/

  def apply_body(message, has_files)
    plain_body = @email.body.to_s.gsub(TEXT_COLOR_MARKER, '').gsub(MD_IMAGE, '[图片]')
    unless @email.body_html.present?
      message.body = plain_body
      message.charset = 'UTF-8'
      return
    end

    source, inline_images = inline_images_as_cid(html_with_tracking_pixel)
    text = Mail::Part.new(body: plain_body, content_type: 'text/plain; charset=UTF-8')
    html = Mail::Part.new(body: source, content_type: 'text/html; charset=UTF-8')
    if inline_images.any?
      message.add_part(related_part(text, html, inline_images))
    elsif has_files
      message.add_part(alternative_part(text, html))
    else
      message.text_part = text
      message.html_part = html
    end
  end

  # text 在前、html 在后：客户端优先展示更"富"的 html。
  def alternative_part(text, html)
    part = Mail::Part.new(content_type: 'multipart/alternative')
    part.add_part(text)
    part.add_part(html)
    part
  end

  AS_BLOB_PATH = %r{/rails/active_storage/blobs/redirect/([^/"]+)/}

  # 发出的副本把站内内联图换成 CID 内嵌附件。
  #
  # 原先内联图是以 <img src="https://wintouchspace.com/rails/active_storage/..."> 发出去的，
  # 链接本身匿名可访问（验过 302→COS 200），但远程图在企业邮箱/工单系统里默认不加载、
  # 不少平台直接把它整段剥掉——我们这边显示"发送成功"，客户那边只看到一行字。
  # 2026-10-26 客户回「这边没有看到有截图哦」，生产上已有 411 封发出的信是这个形态。
  # 截图当场嵌在信里（cid:）才是邮件客户端通用做法，不依赖收件端回站上取图。
  #
  # 取不到的（blob 被删 / 对象存储抽风）保留原链接：不能为一张图把整封信判成发送失败。
  # 引用块的起始标记：由写信弹窗生成（CrmEmailComposeDialog 的 quoteBlockHtml），
  # 样式串在那里写死。编辑器自己的引用按钮走 markdown，出来的是不带 style 的 <blockquote>，
  # 不会误命中。新邮件没有引用块 → 找不到标记 → 整封都算"本次写的"。
  QUOTE_BLOCK = '<blockquote style="margin:8px 0 0;padding-left:12px;border-left:2px solid #d1d5db">'.freeze

  def inline_images_as_cid(html)
    # 只内嵌「本次写的」那一段里的图，引用历史里的图保持原来的远程链接。
    # 一条 46 封往来的长链里攒了 24 张历史图，全嵌单封就 1.4 MB，越回越大；
    # 而那些历史图在收件人自己那份原邮件里本来就有，不用我们再塞一遍。
    cut = html.index(QUOTE_BLOCK) || html.length
    cache = {}
    rewritten = html[0...cut].gsub(/src="([^"]+)"/i) do |matched|
      # ⚠ matched 必须用块参数接住：下一行的 String#[正则] 会重置 Regexp.last_match，
      # 之后再读 last_match(0) 拿到的是 AS_BLOB_PATH 的结果（不匹配时为 nil），
      # 会把追踪像素这类非站内图的 src 整个抹掉。
      signed_id = matched[AS_BLOB_PATH, 1]
      next matched if signed_id.blank?

      cache[signed_id] = downloadable_image(signed_id) unless cache.key?(signed_id)
      image = cache[signed_id]
      image ? %(src="cid:#{image[:cid]}") : matched
    end
    ["#{rewritten}#{html[cut..]}", cache.values.compact]
  end

  def downloadable_image(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    return nil if blob.nil? || !blob.content_type.to_s.start_with?('image/')

    { cid: "#{blob.key}@wintouchspace.com", filename: blob.filename.to_s,
      content_type: blob.content_type, bytes: blob.download }
  rescue StandardError => e
    Rails.logger.warn("[Crm::EmailSend] 内联图取不到，保留原链接 email=#{@email.id} blob=#{signed_id}: #{e.message}")
    nil
  end

  # multipart/related：html 用 cid: 引用，图片作为同层 part 跟在后面。
  # 图片必须和 html 同在 related 里（不能平铺到顶层），否则收件端把它们当普通附件、
  # 正文里的 cid: 解析不到——表现就是"附件有图、正文裂图"。
  def related_part(text, html, images)
    related = Mail::Part.new(content_type: 'multipart/related')
    related.add_part(alternative_part(text, html))
    # ⚠ 别用 related.attachments[...]=：它会把 related 的 Content-Type 重写成
    # multipart/mixed 并连带丢掉 boundary，收件端解析不出子 part（实测重解析后
    # related 底下空无一物）。手工建 part + add_part 才保住 related 和 boundary。
    images.each { |image| related.add_part(inline_part(image)) }
    related
  end

  def inline_part(image)
    part = Mail::Part.new
    part.content_type = %(#{image[:content_type]}; name="#{image[:filename]}")
    part.content_transfer_encoding = 'base64'
    part.content_disposition = %(inline; filename="#{image[:filename]}")
    part.content_id = "<#{image[:cid]}>"
    part.body = [image[:bytes]].pack('m') # 已声明 base64，Mail 不会再编码，这里必须自己编
    part
  end

  # 在 HTML 正文末尾埋 1×1 追踪像素；收件人邮件客户端加载它即命中回调，记录打开。
  # 仅在真正发送的 SMTP 副本注入，CRM 内存的 body_html 保持干净（阅读页不会误触发）。
  def html_with_tracking_pixel
    token = @email.ensure_tracking_token!
    base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    html = rewrite_links_for_tracking(@email.body_html, token, base)
    html = absolutize_attachment_urls(html, base)
    pixel = %(<img src="#{base}/crm_email_open/#{token}.png" width="1" height="1" alt="" style="display:none" />)
    "#{html}#{pixel}"
  end

  # 正文里的内联图（签名 logo、引用的原邮件配图）以站内相对路径存放，
  # 相对路径在收件人的邮件客户端里解析不了，会显示成裂图。发出去的副本补上域名。
  def absolutize_attachment_urls(html, base)
    return html if html.blank?

    html.gsub(%r{src="(/rails/active_storage/[^"]+)"}i) { %(src="#{base}#{Regexp.last_match(1)}") }
  end

  # 把正文里的 http(s) 链接改写成带 token 的跳转链接：收件人点开先命中回调记录点击，再 302 到原地址。
  # 仅重写发出的 SMTP 副本（CRM 内存 body_html 保持干净）；已是追踪链接的跳过。
  def rewrite_links_for_tracking(html, token, base)
    return html if html.blank?

    html.gsub(/href="(https?:\/\/[^"]+)"/i) do
      url = Regexp.last_match(1)
      if url.include?('/crm_email_click/') || url.include?('/crm_email_open/')
        %(href="#{url}")
      else
        %(href="#{base}/crm_email_click/#{token}?u=#{CGI.escape(url)}")
      end
    end
  end

  def smtp_settings(mail_account)
    settings = {
      address: mail_account.resolved_host,
      port: mail_account.resolved_port,
      domain: mail_account.email_address.split('@').last,
      # 坏邮箱（授权码失效/服务器不响应）会让 deliver! 无限阻塞：拖垮 Sidekiq 发信队列，
      # 且留下「PENDING 无错」的僵尸草稿（前端表现为卡发送中/退回草稿）。
      # 加连接/读取超时 → 快速失败落 FAILED + 明确错误，不再无声挂死。
      open_timeout: 15,
      read_timeout: 20
    }
    if mail_account.smtp_password.present?
      settings[:user_name] = mail_account.smtp_user.presence || mail_account.email_address
      settings[:password] = mail_account.smtp_password
      settings[:authentication] = :login
    end
    if mail_account.use_ssl?
      settings[:ssl] = true
    else
      settings[:enable_starttls_auto] = true
    end
    settings
  end

  def fail_with(message)
    @email.update!(send_status: 'FAILED', send_error: message, send_now: false)
    nil
  end
end
