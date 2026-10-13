# 业务员撤回自己发出的那条消息：和在手机上点「为所有人删除」一样，
# 客户客户端里那条会消失。
#
# 认的是消息本身、不认从哪台设备发的，所以业务员在自己手机上发错的那条，
# 也能在 CRM 里撤回。
class Messages::SendRevokeService < Messages::SentMessageMutation
  # WhatsApp 的真实上限是两天多一点；取整两天，留点余量。
  # 卡在边缘发出去，对方客户端可能已经不认了。
  WINDOW = 48.hours

  pattr_initialize [:message!, :user!]

  private

  def action_name = '撤回'

  def expiry_error = '发出超过两天的消息，WhatsApp 不允许再撤回了'

  def deliver
    Whatsapp::BaileysBridgeClient.new.revoke_message(
      channel.session_key, recipient, target_id: message.source_id
    )
  end

  def record
    Messages::RevokeService.new(message: message, by: Messages::RevokeService::AGENT).perform
  end
end
