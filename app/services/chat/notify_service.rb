# 给指定成员发一条团队沟通单聊消息（管理层 → 成员的系统通知，如绩效下发 / 打分结果）。
# 复用已有的单聊去重逻辑；失败只记日志，绝不阻断主业务流程。
class Chat::NotifyService
  def initialize(account:, sender:)
    @account = account
    @sender = sender
  end

  # target_id：接收通知的成员 user_id。content：消息正文。
  def notify(target_id, content)
    return if @sender.nil? || target_id.blank? || target_id == @sender.id

    conversation = Chat::CreateConversationService
                   .new(account: @account, creator: @sender)
                   .find_or_create_direct(target_id)
    conversation.messages.create!(account_id: @account.id, sender_id: @sender.id, content: content)
    conversation.update!(last_message_at: Time.current)
    conversation
  rescue StandardError => e
    Rails.logger.error("[Chat::Notify] sender=#{@sender&.id} to=#{target_id}: #{e.class} #{e.message}")
    nil
  end
end
