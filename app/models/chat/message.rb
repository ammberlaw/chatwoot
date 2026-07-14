# 会话消息。已读回执按各成员的 last_read_message_id 计算（见 jbuilder）。
# == Schema Information
#
# Table name: chat_messages
#
#  id              :bigint           not null, primary key
#  content         :text
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  sender_id       :bigint           not null
#
# Indexes
#
#  index_chat_messages_on_account_id       (account_id)
#  index_chat_messages_on_conversation_id  (conversation_id)
#  index_chat_messages_on_sender_id        (sender_id)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => chat_conversations.id) ON DELETE => cascade
#
class Chat::Message < ApplicationRecord
  belongs_to :account
  belongs_to :conversation, class_name: 'Chat::Conversation', inverse_of: :messages
  belongs_to :sender, class_name: 'User'

  has_many_attached :files

  # 纯附件消息可无正文。
  validates :content, presence: true, unless: -> { files.attached? }

  # 已读人数：除发送者外，last_read_message_id >= 本条 的成员数。
  def read_by_count
    conversation.participants
                .where.not(user_id: sender_id)
                .where('last_read_message_id >= ?', id)
                .count
  end
end
