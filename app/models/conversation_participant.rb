# == Schema Information
#
# Table name: conversation_participants
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
#  index_conversation_participants_on_account_id                   (account_id)
#  index_conversation_participants_on_conversation_id              (conversation_id)
#  index_conversation_participants_on_user_id                      (user_id)
#  index_conversation_participants_on_user_id_and_conversation_id  (user_id,conversation_id) UNIQUE
#
class ConversationParticipant < ApplicationRecord
  validates :account_id, presence: true
  validates :conversation_id, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: [:conversation_id] }
  validate :ensure_inbox_access

  belongs_to :account
  belongs_to :conversation
  belongs_to :user

  before_validation :ensure_account_id

  private

  def ensure_account_id
    self.account_id = conversation&.account_id
  end

  # 原逻辑要求被加的人已经是该收件箱成员。业务员的个人 WhatsApp 收件箱只有他本人一个成员，
  # 那样就永远拉不了同事进来。改成：收件箱成员，或本账号的 CRM 成员（管理员/主管/业务员）皆可。
  # 参与者只能看到自己参与的那几条会话（见 Conversations::PermissionFilterService），
  # 不会因此看到该收件箱里的其他客户。
  def ensure_inbox_access
    return if conversation.blank?
    return if conversation.inbox.assignable_agents.include?(user)
    return if AccountUser.find_by(account_id: conversation.account_id, user_id: user_id)&.can_access_crm?

    errors.add(:user, 'must have inbox access')
  end
end
