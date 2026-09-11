class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  private

  # 被指派人 / 对话参与者也要能打开会话——否则只在列表里看得见、点进去 401。
  # 老板把自己 WhatsApp 上的询盘派给业务员、或把同事拉进来协办，都要靠这两条。
  # 口径与 Conversations::PermissionFilterService 一致：只放开本人被指派或参与的那几条。
  def agent_can_view_conversation?
    inbox_access? || team_access? || assigned_to_user? || participant?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
