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

  # 与列表过滤同一套口径（Conversations::Visibility）——两边一旦走岔，
  # 就会出现「列表里看不到、直接开链接却能看」这种漏。
  # 刻意不再用「是收件箱成员就放行」：公司公共号 15 个成员全是业务员，那等于全公开。
  def agent_can_view_conversation?
    Conversations::Visibility.visible?(record, user, account)
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
