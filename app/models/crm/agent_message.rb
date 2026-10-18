# 对话里的一条。role=tool 的是「它中间查了什么」，照样存下来摆给用户看——
# 不摆的话 AI 说什么就是什么，没人能判断它的结论是从哪儿来的。
# == Schema Information
#
# Table name: crm_agent_messages
#
#  id              :bigint           not null, primary key
#  content         :text
#  duration_ms     :integer
#  input_tokens    :integer
#  meta            :jsonb            not null
#  output_tokens   :integer
#  role            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  conversation_id :bigint           not null
#
# Indexes
#
#  index_crm_agent_messages_on_account_id_and_created_at  (account_id,created_at)
#  index_crm_agent_messages_on_conversation_id            (conversation_id)
#
class Crm::AgentMessage < ApplicationRecord
  self.table_name = 'crm_agent_messages'

  ROLES = %w[user assistant tool].freeze

  belongs_to :account
  belongs_to :conversation, class_name: 'Crm::AgentConversation', inverse_of: :messages

  validates :role, inclusion: { in: ROLES }

  before_validation { self.account_id ||= conversation&.account_id }
end
