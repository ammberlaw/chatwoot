# 某个客户的往来邮件。「调取往来邮件做总结」靠这个。
#
# 邮件走的是**邮件专用权限口径**（老板看全员、CRM 团队负责人看本团队、其余只看自己），
# 比客户的口径更严——邮件是私人往来通信，不能因为能看到这个客户就能看他和别人的通信。
class Crm::Agent::Tools::CustomerEmails < Crm::Agent::Tools::Base
  description '调取某个客户的往来邮件（按时间倒序），用来做往来总结、看谈到哪一步、提取客户要求。先用 find_customer 拿到客户ID。'
  param :customer_id, type: 'integer', desc: '客户ID'
  param :limit, type: 'integer', desc: '最多取几封，默认 15，上限 30', required: false

  # 单封正文给模型看的长度。给太长会把几十封的上下文撑爆，
  # 做往来总结真正有用的是开头那段（报价、要求、交期都在前面）。
  BODY_CLIP = 1200

  def execute(customer_id:, limit: 15)
    customer = scope.customers.find_by(id: customer_id)
    return "看不到 ID #{customer_id} 这个客户。" if customer.nil?

    rows = scope.emails.where(crm_customer_id: customer.id)
                .with_attached_files
                .order(email_date: :desc, id: :desc).limit([limit.to_i, 30].min)
    return "#{customer.name} 名下没有你能看到的往来邮件。" if rows.empty?

    header = "【#{customer.name} 的往来邮件】按时间倒序，共列 #{rows.size} 封：\n"
    header + rows.map { |mail| render(mail) }.join("\n\n")
  end

  private

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
