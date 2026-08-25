# 团队协同实时推送：新消息通过 ActionCable 推给会话所有成员（含发送者的其他设备）。
# 只推轻量信号（会话 id / 发送者 / @提及 / 预览），前端收到后按需增量拉取完整消息，
# 避免在 job 里处理附件 URL / 越权数据。前端按 message id 去重。
class Chat::EventBroadcaster
  EVENT = 'chat.message.created'.freeze

  def self.broadcast_message(conversation, message)
    tokens = conversation.participants.includes(:user).filter_map { |p| p.user&.pubsub_token }
    return if tokens.blank?

    data = {
      account_id: conversation.account_id,
      conversation_id: conversation.id,
      message_id: message.id,
      sender_id: message.sender_id,
      mentioned_ids: message.mentioned_ids,
      preview: message.content.to_s.truncate(60),
      last_message_at: conversation.last_message_at
    }
    ActionCableBroadcastJob.perform_later(tokens, EVENT, data.as_json)
  end
end
