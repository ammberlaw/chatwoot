class AddReplyToToChatMessages < ActiveRecord::Migration[7.1]
  def change
    add_column :chat_messages, :reply_to_id, :bigint
    add_index :chat_messages, :reply_to_id
    add_foreign_key :chat_messages, :chat_messages, column: :reply_to_id, on_delete: :nullify
  end
end
