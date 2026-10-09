# 公司总群的进出：入职自动进、离职自动出。
#
# 原先建群是手工拉人，于是新同事进来没人想起拉他、离职的人一直挂在群里
# （用户反馈：万婷离职停用了还在群里、新账号得手工加）。
# 认的是群上的 auto_join_all 标记，不是群名——群名会改，标记跟着群走。
class Chat::CompanyGroupSync
  def initialize(account)
    @account = account
  end

  def self.on_join(account, user_id) = new(account).join(user_id)
  def self.on_leave(account, user_id) = new(account).leave(user_id)

  # 入职：拉进所有「自动入群」的群（已在群里的跳过，靠唯一索引也兜得住）。
  def join(user_id)
    return if user_id.blank?

    auto_groups.find_each do |conv|
      conv.participants.find_or_create_by!(user_id: user_id) { |p| p.account_id = @account.id }
    end
  end

  # 离职：从这些群里退出。只退自动群——手工拉的项目群留着，
  # 历史消息里他说过的话照常显示（消息不删，只是人不在群里了）。
  def leave(user_id)
    return if user_id.blank?

    Chat::Participant.where(conversation_id: auto_groups.select(:id), user_id: user_id).destroy_all
  end

  private

  def auto_groups
    @account.chat_conversations.where(kind: 'group', auto_join_all: true)
  end
end
