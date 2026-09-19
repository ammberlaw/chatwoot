class Conversations::PermissionFilterService
  attr_reader :conversations, :user, :account

  def initialize(conversations, user, account)
    @conversations = conversations
    @user = user
    @account = account
  end

  def perform
    return conversations if user_role == 'administrator'

    accessible_conversations
  end

  private

  # 口径收敛在 Conversations::Visibility（列表 / 单条鉴权 / 实时推送三处共用）：
  # 公司公共号只看分到自己头上的，个人号整箱可见，另加被拉进去参与的那几条。
  def accessible_conversations
    Conversations::Visibility.scope_for(conversations, user, account)
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
