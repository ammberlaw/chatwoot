# 对话里的一条。role=tool 的是「它中间查了什么」，照样存下来摆给用户看——
# 不摆的话 AI 说什么就是什么，没人能判断它的结论是从哪儿来的。
class Crm::AgentMessage < ApplicationRecord
  self.table_name = 'crm_agent_messages'

  ROLES = %w[user assistant tool].freeze

  belongs_to :account
  belongs_to :conversation, class_name: 'Crm::AgentConversation', inverse_of: :messages

  validates :role, inclusion: { in: ROLES }

  before_validation { self.account_id ||= conversation&.account_id }
end
