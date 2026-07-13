# 建会话：单聊按双方去重（已存在则复用），群聊新建并拉成员。
class Chat::CreateConversationService
  def initialize(account:, creator:)
    @account = account
    @creator = creator
  end

  # 单聊：找 creator 与 target 之间已有的 direct 会话，没有则建。
  def find_or_create_direct(target_id)
    existing = existing_direct(target_id)
    return existing if existing

    conversation = @account.chat_conversations.create!(kind: 'direct', creator_id: @creator.id)
    add_participants(conversation, [@creator.id, target_id])
    conversation
  end

  # 群聊：名称 + 成员（自动含创建者）。
  def create_group(name:, user_ids:)
    conversation = @account.chat_conversations.create!(kind: 'group', name: name, creator_id: @creator.id)
    add_participants(conversation, ([@creator.id] + Array(user_ids)).uniq)
    conversation
  end

  private

  def existing_direct(target_id)
    with_me = Chat::Participant.where(user_id: @creator.id).select(:conversation_id)
    with_target = Chat::Participant.where(user_id: target_id).select(:conversation_id)
    @account.chat_conversations.where(kind: 'direct', id: with_me).where(id: with_target).first
  end

  def add_participants(conversation, user_ids)
    user_ids.each do |uid|
      conversation.participants.create!(account_id: @account.id, user_id: uid)
    end
  end
end
