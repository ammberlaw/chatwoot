# 消息被编辑（WhatsApp 的「编辑」）。入站（客户改了他那条）和出站（业务员改自己那条）
# 共用，保证两边落库形状一致。
#
# 不留旧版本：WhatsApp 只显示最新内容加一个「已编辑」标记，CRM 跟着它来，
# 否则同一条消息在手机上和 CRM 里对不上。
class Messages::EditService
  pattr_initialize [:message!, :content!]

  def perform
    attrs = message.content_attributes.dup
    attrs['edited_at'] = Time.current.to_i
    # 只改正文：content_type 和附件都不动（能编辑的本来就只有纯文字消息）。
    message.update!(content: content.to_s, content_attributes: attrs)
    message
  end
end
