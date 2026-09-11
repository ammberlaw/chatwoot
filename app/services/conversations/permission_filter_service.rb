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

  # 收件箱成员能看本收件箱的会话；另外，被同事拉进某条会话当「对话参与者」的人也要能看到
  # 那一条——业务员的个人 WhatsApp 收件箱只有他自己是成员，不放开的话拉人进来等于没拉。
  # 只放开参与的那几条，不是整个收件箱，避免看到别人 WhatsApp 里的其他客户。
  def accessible_conversations
    conversations.where(inbox: user.inboxes.where(account_id: account.id))
                 .or(conversations.where(id: user.participating_conversations.select(:id)))
  end

  def account_user
    AccountUser.find_by(account_id: account.id, user_id: user.id)
  end

  def user_role
    account_user&.role
  end
end

Conversations::PermissionFilterService.prepend_mod_with('Conversations::PermissionFilterService')
