# 业务员改自己刚发出的那条消息：和手机上点「编辑」一样，
# 客户那边的消息会变成新内容，底下挂一个「已编辑」。
class Messages::SendEditService < Messages::SentMessageMutation
  # WhatsApp 的硬限制，改不了：超过 15 分钟发过去对方客户端直接忽略。
  WINDOW = 15.minutes

  pattr_initialize [:message!, :user!, :content!]

  private

  def action_name = '编辑'

  def expiry_error = '发出超过 15 分钟的消息，WhatsApp 不允许再编辑了'

  # WhatsApp 只让编辑纯文字那条：带图/带文件的改不了（它改的是正文，不是附件）。
  def extra_validate!
    raise Error, '编辑后的内容不能为空' if content.to_s.strip.blank?
    raise Error, '带附件的消息不能编辑，只能撤回重发' if message.attachments.any?
  end

  def deliver
    Whatsapp::BaileysBridgeClient.new.edit_message(
      channel.session_key, recipient, target_id: message.source_id, text: content.to_s.strip
    )
  end

  def record
    Messages::EditService.new(message: message, content: content.to_s.strip).perform
  end
end
