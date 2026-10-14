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
                .order(email_date: :desc, id: :desc).limit([limit.to_i, 30].min)
    return "#{customer.name} 名下没有你能看到的往来邮件。" if rows.empty?

    header = "【#{customer.name} 的往来邮件】按时间倒序，共列 #{rows.size} 封：\n"
    header + rows.map { |mail| render(mail) }.join("\n\n")
  end

  private

  def render(mail)
    <<~TXT.strip
      — #{day(mail.email_date)}｜#{direction(mail)}｜主题：#{clip(mail.subject, 120).presence || '（无主题）'}
      发件 #{clip(mail.from_address, 80)}　收件 #{clip(mail.to_address, 80)}
      #{clip(plain_body(mail), BODY_CLIP)}
    TXT
  end

  # 我方发出还是客户发来：往来总结里「谁说的」比内容本身还关键。
  def direction(mail)
    mail.send_status.present? || mail.folder.to_s.casecmp('sent').zero? ? '我方发出' : '客户发来'
  end

  # 优先纯文本；只有 HTML 的把标签去掉——带标签喂给模型既占长度又干扰理解。
  def plain_body(mail)
    return mail.body if mail.body.present?

    ActionView::Base.full_sanitizer.sanitize(mail.body_html.to_s).to_s.squish
  end
end
