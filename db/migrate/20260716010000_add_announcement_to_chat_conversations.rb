class AddAnnouncementToChatConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :chat_conversations, :announcement, :text
  end
end
