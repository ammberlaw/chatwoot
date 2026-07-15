class Chat::ConversationPolicy < ApplicationPolicy
  # 团队沟通对所有账号成员开放；具体会话的可见性由控制器（仅参与者）保证。
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def read?
    true
  end

  # 群主校验在控制器 ensure_group_owner 完成。
  def update?
    true
  end

  def remove_participant?
    true
  end

  def transfer_owner?
    true
  end

  def leave?
    true
  end
end

Chat::ConversationPolicy.prepend_mod_with('Chat::ConversationPolicy')
