# 官方号（Cloud API）收到的表情回应。
#
# webhook 形状：{ type: 'reaction', reaction: { message_id: 被回应那条, emoji: '❤️' } }。
# emoji 为空表示客户撤销了回应。
#
# 回应不是一条新消息，所以不建 Message，只挂到被回应的那条上。被回应的消息不在
# CRM 里（接入之前的老消息）就丢弃——没有载体可挂。
#
# 与个人号那条线（IncomingReactionWhatsappWebService）落库形状一致，前端只认一种。
class Whatsapp::IncomingReactionService
  pattr_initialize [:inbox!, :data!]

  def perform
    return if target.nil? || contact.nil?

    Messages::ReactionService.new(
      message: target,
      actor: Messages::ReactionService::CONTACT,
      actor_id: contact.id,
      actor_name: contact.name,
      emoji: data.dig(:reaction, :emoji).presence,
      source_id: data[:id]
    ).perform
  end

  private

  def target
    @target ||= inbox.messages.find_by(source_id: data.dig(:reaction, :message_id))
  end

  def contact
    @contact ||= target.conversation.contact
  end
end
