class Conversations::UnreadCounts::BroadcastScope
  attr_reader :event

  def initialize(event)
    @event = event
  end

  def perform
    # 未读数变化只推给看得见这条会话的人（口径同 Conversations::Visibility）。
    # 会话已被删的那条分支拿不到指派人，只能按收件箱成员推——但那时 payload 是空的 {}，
    # 推多了也不泄露内容。
    return [conversation.account, Conversations::Visibility.audience(conversation)] if conversation.present?

    deleted_conversation_scope
  end

  private

  def conversation
    event.data[:conversation]
  end

  def deleted_conversation_scope
    conversation_data = event.data[:conversation_data]&.with_indifferent_access
    return if conversation_data.blank?

    account = Account.find_by(id: conversation_data[:account_id])
    return if account.blank?

    [account, inbox_members_for(account, conversation_data[:inbox_id])]
  end

  def inbox_members_for(account, inbox_id)
    inbox = account.inboxes.find_by(id: inbox_id)
    return User.none if inbox.blank?

    inbox.members
  end
end
