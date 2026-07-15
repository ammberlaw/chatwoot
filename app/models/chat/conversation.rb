# 组织内部会话（团队沟通）：单聊(direct) 或 群聊(group)。对内 IM，与客服会话无关。
# == Schema Information
#
# Table name: chat_conversations
#
#  id              :bigint           not null, primary key
#  announcement    :text
#  kind            :string           default("direct"), not null
#  last_message_at :datetime
#  name            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  creator_id      :bigint
#
# Indexes
#
#  index_chat_conversations_on_account_id  (account_id)
#
class Chat::Conversation < ApplicationRecord
  KINDS = %w[direct group].freeze

  belongs_to :account
  has_many :participants, class_name: 'Chat::Participant', inverse_of: :conversation, dependent: :destroy
  has_many :messages, class_name: 'Chat::Message', inverse_of: :conversation, dependent: :destroy
  has_many :users, through: :participants

  validates :kind, inclusion: { in: KINDS }

  scope :for_user, ->(user_id) { joins(:participants).where(chat_participants: { user_id: user_id }) }
  scope :recent, lambda {
    order(Arel.sql('COALESCE(chat_conversations.last_message_at, chat_conversations.created_at) DESC'))
  }

  def direct?
    kind == 'direct'
  end

  # 单聊显示为对方名字；群聊显示群名。
  def display_name_for(user_id)
    return name if kind == 'group'

    participants.includes(:user).find { |p| p.user_id != user_id }&.user&.name || '(空会话)'
  end

  def peer_participant(user_id)
    participants.includes(:user).find { |p| p.user_id != user_id }
  end

  def unread_count_for(user_id)
    part = participants.find_by(user_id: user_id)
    return 0 unless part

    messages.where.not(sender_id: user_id).where('id > ?', part.last_read_message_id || 0).count
  end
end
