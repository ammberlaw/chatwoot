class CreateChatMessaging < ActiveRecord::Migration[7.1]
  def change
    create_conversations
    create_participants
    create_messages
  end

  def create_conversations
    create_table :chat_conversations do |t|
      t.bigint :account_id, null: false, index: true
      t.string :kind, default: 'direct', null: false
      t.string :name
      t.bigint :creator_id
      t.datetime :last_message_at
      t.timestamps
    end
  end

  def create_participants
    create_table :chat_participants do |t|
      t.bigint :account_id, null: false, index: true
      t.references :conversation, null: false, foreign_key: { to_table: :chat_conversations, on_delete: :cascade }
      t.bigint :user_id, null: false, index: true
      t.bigint :last_read_message_id
      t.datetime :last_read_at
      t.timestamps
      t.index [:conversation_id, :user_id], unique: true, name: 'index_chat_participants_unique'
    end
  end

  def create_messages
    create_table :chat_messages do |t|
      t.bigint :account_id, null: false, index: true
      t.references :conversation, null: false, foreign_key: { to_table: :chat_conversations, on_delete: :cascade }
      t.bigint :sender_id, null: false, index: true
      t.text :content
      t.timestamps
    end
  end
end
