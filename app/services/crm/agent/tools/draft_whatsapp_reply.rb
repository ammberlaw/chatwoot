# 给 WhatsApp 对话写一版回复——**存成私密备注，绝不发给客户**。
#
# WhatsApp 和邮件不一样：Chatwoot 的会话没有「草稿」这个东西，消息一建就发出去了。
# 所以这里落成**私密备注**（private: true）——它只在会话里给自己人看，
# 客户那边永远收不到。业务员看完觉得行，自己复制到输入框发出去。
#
# 这是唯一既能「把写好的话留在对话里、手机上也看得到」，又能守住
# 「什么都不许往外发」这条硬规矩的做法。
class Crm::Agent::Tools::DraftWhatsappReply < Crm::Agent::Tools::Base
  writes_data

  description '给某个 WhatsApp 对话写一版回复建议，存成会话里的私密备注（**客户收不到**）。' \
              '业务员自己看完再决定发不发。会话编号从 whatsapp_thread 的结果里取。'
  param :conversation_id, type: 'integer', desc: '会话编号（whatsapp_thread 结果里的「WhatsApp 对话 #123」那个数字）'
  param :body, desc: '回复正文。按客户用的语言写，只写要说的话。'

  def execute(conversation_id:, body:)
    text = body.to_s.strip
    return '回复正文是空的，没写备注。' if text.blank?

    conv = scope.whatsapp_conversations.find_by(display_id: conversation_id.to_i)
    return "看不到会话 ##{conversation_id}（它可能不在你的 WhatsApp 号里）。" if conv.nil?

    note = build_note(conv, text)
    return '备注没建成功，请稍后再试。' if note.blank?

    scope.record_artifact(kind: 'whatsapp_note', id: conv.display_id,
                          customer_id: conv.contact&.crm_customer_id,
                          label: "WhatsApp 回复建议 ##{conv.display_id}")
    "已把回复建议写进 WhatsApp 对话 ##{conv.display_id} 的**私密备注**（#{conv.contact&.name.presence || '未命名'}）。" \
      '客户看不到这条。去 WhatsApp 对话里看一眼，确认无误再自己复制发出去。'
  end

  private

  # 备注开头标明是 AI 写的：一条私密备注混在同事的内部沟通里，
  # 不标清楚来源，下次有人看到会以为是哪个同事的结论。
  PREFIX = '【AI 回复建议 · 未发送】'.freeze

  def build_note(conv, text)
    user = scope.user
    return nil if user.blank?

    Messages::MessageBuilder.new(user, conv.reload, { content: "#{PREFIX}\n#{text}", private: true }).perform
  rescue StandardError => e
    Rails.logger.warn("[crm_agent] draft_whatsapp_reply 失败 conv=#{conv.id}: #{e.class} #{e.message}")
    nil
  end
end
