# 某个客户的往来邮件。「调取往来邮件做总结」靠这个。
#
# 邮件走的是**邮件专用权限口径**（老板看全员、CRM 团队负责人看本团队、其余只看自己），
# 比客户的口径更严——邮件是私人往来通信，不能因为能看到这个客户就能看他和别人的通信。
class Crm::Agent::Tools::CustomerEmails < Crm::Agent::Tools::Base
  description '调取往来邮件（按时间倒序），用来做往来总结、看谈到哪一步、提取客户要求。' \
              '三种叫法：给 customer_id＝看这个客户的全部往来（先用 find_customer 拿ID）；' \
              '给 email_id＝**只知道一封信的ID时用这个**，会把这封信读出来并带上同客户的其他往来；' \
              '给 query＝**用户把邮件原文粘进来、或只报得出发件人邮箱和主题时用这个**，' \
              '按发件人/收件人/主题去找那封信，找到了就有邮件ID，接着才能 draft_reply。' \
              '要回信就先把原文读一遍，别拿着ID直接 draft_reply——没读过原文写不出回复。'
  param :customer_id, type: 'integer', desc: '客户ID', required: false
  param :email_id, type: 'integer', desc: '某一封邮件的ID（用户正开着那封信时就是它）', required: false
  param :query, type: 'string', desc: '发件人邮箱、收件人邮箱或主题里的关键词', required: false
  param :limit, type: 'integer', desc: '最多取几封，默认 15，上限 30', required: false

  # 单封正文给模型看的长度。给太长会把几十封的上下文撑爆，
  # 做往来总结真正有用的是开头那段（报价、要求、交期都在前面）。
  BODY_CLIP = 1200

  def execute(customer_id: nil, email_id: nil, query: nil, limit: 15)
    return search(query, limit) if customer_id.blank? && email_id.blank? && query.present?

    focused = email_id.present? ? scope.emails.find_by(id: email_id) : nil
    customer = resolve_customer(customer_id, focused)
    blocker_for(customer_id, email_id, focused, customer) || thread_text(customer, focused, limit)
  end

  def thread_text(customer, focused, limit)
    # 这封信还没建档到客户名下（邮件建档是后一步），那就只把它本身读出来。
    return single(focused) if customer.nil?

    rows = thread_rows(customer, focused, limit)
    return "#{customer.name} 名下没有你能看到的往来邮件。" if rows.empty?

    header(customer, focused, rows.size) + rows.map { |mail| render(mail) }.join("\n\n")
  end

  private

  # 按发件人/收件人/主题找信。
  #
  # 为什么必须有这条路：全库 6122 封邮件里有 2732 封（44.6%）没挂到任何客户名下，
  # 只按 customer_id 查就有近一半概率扑空——信明明在库里。
  # 2026-10-29 生产上真发生过：业务员把一封询盘原文整段粘进来，助手调了 21 次工具、
  # 查遍产品档案，最后回头跟她要「邮件ID」；而那封信就躺在库里（ID 6195），
  # 她给的发件人邮箱和主题足够把它捞出来。
  def search(query, limit)
    q = query.to_s.strip
    return '搜邮件至少给一个发件人邮箱或主题关键词。' if q.length < 2

    rows = matching_emails(q, limit)
    return "没找到发件人/收件人/主题里带「#{q}」的邮件。换个关键词，或者确认这封信有没有收进系统。" if rows.empty?

    "【按「#{q}」找到 #{rows.size} 封】要回哪一封，就拿它的邮件ID去 draft_reply：\n" +
      rows.map { |mail| render(mail) }.join("\n\n")
  end

  def matching_emails(query, limit)
    like = "%#{query.downcase}%"
    scope.emails
         .where('LOWER(from_address) LIKE :q OR LOWER(to_address) LIKE :q OR LOWER(subject) LIKE :q',
                q: like)
         .with_attached_files
         .order(email_date: :desc, id: :desc)
         .limit([limit.to_i, 30].min)
  end

  def resolve_customer(customer_id, focused)
    id = customer_id.presence || focused&.crm_customer_id
    id && scope.customers.find_by(id: id)
  end

  def blocker_for(customer_id, email_id, focused, customer)
    return 'customer_id、email_id、query 三个里至少给一个。' if customer_id.blank? && email_id.blank?
    return "看不到 ID #{email_id} 这封邮件（它可能不在你的可见范围内）。" if email_id.present? && focused.nil?

    "看不到 ID #{customer_id} 这个客户。" if customer_id.present? && customer.nil?
  end

  # 指名的那封排第一，后面接同客户的往来——回信要的就是「这封说了什么」+「之前谈到哪」。
  def thread_rows(customer, focused, limit)
    rest = scope.emails.where(crm_customer_id: customer.id)
                .where.not(id: focused&.id)
                .with_attached_files
                .order(email_date: :desc, id: :desc).limit([limit.to_i, 30].min)
    [focused, *rest].compact
  end

  def header(customer, focused, count)
    return "【#{customer.name} 的往来邮件】按时间倒序，共列 #{count} 封：\n" if focused.nil?

    "【#{customer.name}】第一封就是你要看的那封（邮件ID #{focused.id}），" \
      "后面 #{count - 1} 封是之前的往来：\n"
  end

  def single(mail)
    "【邮件ID #{mail.id}】这封信还没归到某个客户名下：\n#{render(mail)}"
  end

  def render(mail)
    <<~TXT.strip
      — 邮件ID #{mail.id}｜#{day(mail.email_date)}｜#{direction(mail)}｜主题：#{clip(mail.subject, 120).presence || '（无主题）'}
      发件 #{clip(mail.from_address, 80)}　收件 #{clip(mail.to_address, 80)}#{attachment_line(mail)}
      #{clip(plain_body(mail), BODY_CLIP)}
    TXT
  end

  # 附件名要摆出来：客户的询价表、规格书、PI 常常**只在附件里**，正文就一句
  # 「see attached」。列出来模型才知道有东西可读，接着用 read_attachment 去抽明细。
  def attachment_line(mail)
    names = mail.files.attachments.map { |a| a.blob.filename.to_s }
    return '' if names.empty?

    "\n附件（#{names.size} 个，可用 read_attachment 读）：#{names.each_with_index.map { |n, i| "#{i + 1}. #{n}" }.join('　')}"
  end

  # 我方发出还是客户发来：往来总结里「谁说的」比内容本身还关键。
  #
  # ⚠️ 只能看 folder。原来那个判断里带了 send_status.present?，而这一列是
  # NOT NULL default 'DRAFT'——任何一封信它都 present?，于是恒真：
  # 客户发来的信全被标成「我方发出」，模型据此把方向读反
  # （客户问「能不能支持 24V」被总结成「我们已答应 24V」）。
  OUTBOUND_FOLDERS = %w[SENT DRAFT].freeze

  def direction(mail)
    OUTBOUND_FOLDERS.include?(mail.folder.to_s.upcase) ? '我方发出' : '客户发来'
  end

  # 优先纯文本；只有 HTML 的把标签去掉——带标签喂给模型既占长度又干扰理解。
  def plain_body(mail)
    return mail.body if mail.body.present?

    ActionView::Base.full_sanitizer.sanitize(mail.body_html.to_s).to_s.squish
  end
end
