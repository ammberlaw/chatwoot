# 业务员在 CRM 里对某条消息做表情回应，发到对应渠道去。
#
# 先发后记：外发失败就不落库，免得 CRM 里显示「我回应了 ❤️」而客户手机上
# 其实什么都没有。emoji 传空 = 撤销（WhatsApp 两端都用空字符串表达撤销）。
#
# 目前只有 WhatsApp 两条线支持；其它渠道抛 UnsupportedChannel，控制器转成 422。
class Messages::SendReactionService
  class UnsupportedChannel < StandardError; end

  pattr_initialize [:message!, :user!, { emoji: nil }]

  def perform
    deliver
    Messages::ReactionService.new(
      message: message,
      actor: Messages::ReactionService::AGENT,
      actor_id: user.id,
      actor_name: user.name,
      emoji: emoji
    ).perform
  end

  private

  def channel
    @channel ||= message.inbox.channel
  end

  def deliver
    case message.inbox.channel_type
    when 'Channel::WhatsappWeb' then deliver_whatsapp_web
    when 'Channel::Whatsapp' then deliver_whatsapp_cloud
    else raise UnsupportedChannel, "#{message.inbox.channel_type} 还不支持表情回应"
    end
  end

  # 个人号：桥照 Baileys 的 react 语义发，需要被回应那条的 id 和方向
  # （fromMe 决定 key 怎么拼，拼错了客户端不认这条回应）。
  def deliver_whatsapp_web
    Whatsapp::BaileysBridgeClient.new.send_reaction(
      channel.session_key,
      message.conversation.contact_inbox.source_id,
      target_id: message.source_id,
      from_me: message.outgoing?,
      emoji: emoji.to_s
    )
  end

  def deliver_whatsapp_cloud
    channel.provider_service.send_reaction(
      message.conversation.contact_inbox.source_id,
      target_id: message.source_id,
      emoji: emoji.to_s
    )
  end
end
