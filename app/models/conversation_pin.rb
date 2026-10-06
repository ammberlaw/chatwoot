# == Schema Information
#
# Table name: conversation_pins
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_conversation_pins_on_account_id_and_user_id  (account_id,user_id)
#  index_conversation_pins_on_conversation_id         (conversation_id)
#  index_conversation_pins_on_user_and_conversation   (user_id,conversation_id) UNIQUE
#
# 会话置顶：每个人钉自己的，互不影响。钉住的会话在列表里排在最前。
class ConversationPin < ApplicationRecord
  MAX_PER_USER = 10

  belongs_to :account
  belongs_to :user
  belongs_to :conversation

  validates :conversation_id, uniqueness: { scope: :user_id }

  # 列表一页 25 行，逐行 exists? 就是 25 条查询。一次请求只查一次，缓在 Current 上。
  def self.pinned?(conversation)
    return false if Current.user.blank?

    Current.pinned_conversation_ids ||= where(user_id: Current.user.id,
                                              account_id: conversation.account_id).pluck(:conversation_id).to_set
    Current.pinned_conversation_ids.include?(conversation.id)
  end
end
