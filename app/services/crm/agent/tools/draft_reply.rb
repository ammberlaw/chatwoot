# 回复某一封往来邮件——存草稿，**不发**。
#
# 和 draft_email 的分工：那个是「给这个客户新写一封」，这个是「回他刚才那封」。
# 两件事在用户嘴里都叫「写邮件」，但产物不一样：回复要接着原来那封谈，
# 收件人、主题、引用原文都该由系统填好，不该让模型自己拼——它拼就会出现
# 把「Re: Re: Re:」越叠越长、或者把引用原文当正文重写一遍这类事。
#
# 收件人怎么定：客户发来的信 → 回给发件人；我方发出的信 → 继续发给原收件人
# （「再催一下上封那个」是回自己发出去那封，收件人当然还是客户）。
#
# 引用格式和界面上人工点「回复」完全一致（CrmEmailsIndex 的 quotedBody），
# 这样草稿在邮件撰写框里打开时看不出是 AI 建的还是人建的。
class Crm::Agent::Tools::DraftReply < Crm::Agent::Tools::Base
  description '回复某一封往来邮件：存成草稿（不会发送）。收件人、Re: 主题、原文引用都由工具填好，' \
              '你只写回复正文。不需要先知道是哪个客户——客户、收件人都由这封信自己带出来。' \
              '⚠️ **但必须先读过这封信**：先 customer_emails(email_id: 这封的ID) 看客户问了什么，' \
              '再照着问题写正文。没读就调这个＝写出一句「正在核对」的空草稿，等于没回。' \
              '连ID都没有时，先用 customer_emails 找。'
  param :email_id, type: 'integer', desc: '要回复的那封邮件的 ID（customer_emails 列出来的「邮件ID #123」）'
  param :body, desc: '回复正文（纯文本，按客户所在国家的语言写）。**只写你要说的话**，' \
                     '不要自己抄一遍原邮件——引用由工具附在下面。'

  # 我方发出的信（含草稿）：回它＝继续发给原收件人。
  OUTBOUND_FOLDERS = %w[SENT DRAFT].freeze

  def execute(email_id:, body:)
    src = scope.emails.find_by(id: email_id)
    return "看不到 ID #{email_id} 这封邮件（它可能不在你的可见范围内）。" if src.nil?
    return '回复正文是空的，没建草稿。' if body.to_s.strip.blank?

    to = reply_to_address(src)
    return "这封邮件上没有可回复的地址（原邮件 #{email_id} 的发件/收件地址都是空的），没建草稿。" if to.blank?

    draft = create_draft(src, body, to)
    scope.record_artifact(kind: 'email_draft', id: draft.id, customer_id: src.crm_customer_id,
                          label: "回复草稿：#{draft.subject.to_s.strip.truncate(24)}")
    "已回复存成草稿（草稿 #{draft.id}）→ #{to}，主题「#{draft.subject}」，原邮件已引用在正文下方。" \
      '**还没有发送**，请到「邮件 → 草稿箱」检查无误后自己点发送。'
  end

  private

  def reply_to_address(src)
    outbound = OUTBOUND_FOLDERS.include?(src.folder.to_s.upcase)
    (outbound ? src.to_address : src.from_address).presence || src.from_address.presence
  end

  # 主题前缀只加一次：原本就是 Re:（含 RE:／re:）开头的就原样沿用，
  # 不然一来一回几轮下来标题全是「Re: Re: Re: Re:」。
  def reply_subject(src)
    subject = src.subject.to_s.strip
    return 'Re: (无主题)' if subject.blank?

    subject.match?(/\Are\s*:/i) ? subject : "Re: #{subject}"
  end

  # 引用块格式与界面上人工点「回复」一致（见 CrmEmailsIndex 的 quotedBody）。
  def quoted(src)
    <<~TXT

      ------ 原邮件 ------
      发件人：#{src.from_address.presence || '—'}
      时间：#{src.email_date&.strftime('%Y-%m-%d %H:%M') || '—'}
      主题：#{src.subject.presence || '(无主题)'}

      #{src.body}
    TXT
  end

  def create_draft(src, body, to_address)
    scope.account.crm_emails.create!(
      owner_id: scope.user_id, crm_customer_id: src.crm_customer_id,
      folder: 'DRAFT', send_status: 'DRAFT',
      subject: reply_subject(src), body: "#{body.to_s.strip}\n#{quoted(src)}",
      to_address: to_address, email_date: Time.current
    )
  end
end
