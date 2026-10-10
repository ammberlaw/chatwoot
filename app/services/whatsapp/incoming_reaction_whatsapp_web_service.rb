# 个人号（Baileys）收到的表情回应。
#
# 桥转过来的是「谁对哪条消息回应了什么」，不是一条新消息，所以不建 Message，
# 只把回应挂到被回应的那条上（Messages::ReactionService）。
#
# 被回应的消息可能根本不在 CRM 里（配对之前的老消息、或当时没收进来），
# 这种就直接丢弃——没有载体可挂，硬建一条占位消息只会把会话搞乱。
class Whatsapp::IncomingReactionWhatsappWebService
  pattr_initialize [:inbox!, :params!]

  def perform
    return if target.nil?

    Messages::ReactionService.new(
      message: target,
      actor: from_me? ? Messages::ReactionService::AGENT : Messages::ReactionService::CONTACT,
      actor_id: actor_id,
      actor_name: actor_name,
      emoji: params[:emoji].presence,
      source_id: params[:source_id].presence
    ).perform
  end

  private

  # target_id 是被回应那条消息在 WhatsApp 上的 id，与我们入库时的 source_id 同源。
  def target
    @target ||= inbox.messages.find_by(source_id: params[:target_id].presence)
  end

  # 业务员在手机上回应的，记在收件箱归属人名下（个人号收件箱只有他本人）。
  def from_me?
    ActiveModel::Type::Boolean.new.cast(params[:from_me]).present?
  end

  def agent
    @agent ||= inbox.inbox_members.first&.user
  end

  def actor_id
    from_me? ? agent&.id : target.conversation.contact_id
  end

  def actor_name
    from_me? ? agent&.name : target.conversation.contact&.name
  end
end
