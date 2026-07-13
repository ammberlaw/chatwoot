# 会话成员：记录每个人在某会话中的已读进度（last_read_message_id）。
# == Schema Information
#
# Table name: chat_participants
#
#  id                   :bigint           not null, primary key
#  last_read_at         :datetime
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  conversation_id      :bigint           not null
#  last_read_message_id :bigint
#  user_id              :bigint           not null
#
class Chat::Participant < ApplicationRecord
  belongs_to :account
  belongs_to :conversation, class_name: 'Chat::Conversation', inverse_of: :participants
  belongs_to :user

  validates :user_id, uniqueness: { scope: :conversation_id }
end
