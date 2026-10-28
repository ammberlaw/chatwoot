# 读 WhatsApp 对话：客户在 WhatsApp 上说了什么。
#
# 为什么单独一个工具而不是复用 customer_emails：WhatsApp 消息不在 crm_emails 里，
# 而在 Chatwoot 自己的 conversations/messages。而且**绝大多数 WhatsApp 联系人没有
# 关联 CRM 客户**——生产实测 342 个联系人里，手机号能匹配上 CRM 客户的只有 17 个（5%）。
# 所以这个工具不能要求先有 customer_id，得能直接按手机号/名字/会话号找到那串对话。
class Crm::Agent::Tools::WhatsappThread < Crm::Agent::Tools::Base
  description '读某个客户在 WhatsApp 上的对话记录（按手机号、联系人名或会话编号找）。' \
              '问「客户在 WhatsApp 上说了什么」「他微信/WhatsApp 问的那个价回了没」用这个——' \
              'WhatsApp 的消息不在邮件里，customer_emails 查不到。'
  param :keyword, desc: '手机号、联系人名，或会话编号（#123）', required: false
  param :limit, type: 'integer', desc: '最多回几条消息，默认 20，上限 50', required: false

  CLIP = 300

  def execute(keyword: nil, limit: 20)
    n = limit.to_i.positive? ? [limit.to_i, 50].min : 20
    convs = find_conversations(keyword)
    return empty_text(keyword) if convs.empty?

    convs.first(3).map { |c| render(c, n) }.join("\n\n")
  end

  private

  def find_conversations(keyword)
    base = scope.whatsapp_conversations.includes(:contact, :inbox).order(last_activity_at: :desc)
    kw = keyword.to_s.strip
    return base.limit(3).to_a if kw.blank?

    return base.where(display_id: kw.delete('#').to_i).limit(1).to_a if kw.match?(/\A#?\d+\z/)

    digits = kw.gsub(/\D/, '')
    rel = base.joins(:contact)
    rel = if digits.length >= 6
            rel.where("regexp_replace(COALESCE(contacts.phone_number,''), '[^0-9]', '', 'g') LIKE ?", "%#{digits}")
          else
            rel.where('contacts.name ILIKE :t OR contacts.email ILIKE :t', t: "%#{kw}%")
          end
    rel.limit(3).to_a
  end

  def empty_text(keyword)
    kw = keyword.to_s.strip
    return '你名下的 WhatsApp 收件箱里还没有对话。' if kw.blank?

    "WhatsApp 里没找到「#{kw}」的对话（只在你自己的 WhatsApp 号里找）。"
  end

  def render(conv, limit)
    contact = conv.contact
    head = "【WhatsApp 对话 ##{conv.display_id}】#{contact&.name.presence || '未命名'}" \
           "#{contact&.phone_number.present? ? "（#{contact.phone_number}）" : ''}｜#{conv.inbox&.name}"
    head += customer_line(contact)
    rows = conv.messages.where(private: false).where.not(message_type: 2)
               .order(created_at: :desc).limit(limit).to_a.reverse
    return "#{head}\n  （还没有消息）" if rows.empty?

    "#{head}\n#{rows.map { |m| line(m) }.join("\n")}"
  end

  # 关没关联 CRM 客户必须说清楚：没关联时模型就不该去查这家的历史报价和订单
  # （查出来的是别人家的），只能基于对话本身和产品资料回答。
  def customer_line(contact)
    return '｜⚠️ 这个号还没关联 CRM 客户档案（查不到他的历史报价和订单）' if contact&.crm_customer_id.blank?

    name = Crm::Customer.find_by(id: contact.crm_customer_id)&.name
    "｜已关联客户：#{name}（客户ID #{contact.crm_customer_id}）"
  end

  def line(msg)
    who = msg.message_type == 'outgoing' || msg.message_type == 1 ? '我方' : '客户'
    time = msg.created_at&.strftime('%m-%d %H:%M')
    body = clip(msg.content.to_s.strip, CLIP).presence || '（无文字内容）'
    att = msg.attachments.any? ? "［带附件 #{msg.attachments.size} 个］" : ''
    "  #{time} #{who}：#{body}#{att}"
  end
end
