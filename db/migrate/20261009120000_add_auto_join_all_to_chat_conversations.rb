# 公司总群：新成员自动入群、离职自动退群。
# 用一个标记位而不是按群名硬匹配——群名会改（「东莞市联迪科技有限公司」），
# 标记跟着群走，以后换一个总群改这一行数据就行。
class AddAutoJoinAllToChatConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :chat_conversations, :auto_join_all, :boolean, default: false, null: false
    add_index :chat_conversations, [:account_id, :auto_join_all],
              where: 'auto_join_all', name: 'index_chat_conversations_auto_join'
  end
end
