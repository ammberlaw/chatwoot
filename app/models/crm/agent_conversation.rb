# CRM AI 助手的一次对话。
#
# agent 取数一律用 user 的权限（见 Crm::Agent::Tools::Base#scope_for）——
# 业务员让它查客户/翻邮件，看到的和他自己点进去看到的必须一样，不能借 AI 越权。
class Crm::AgentConversation < ApplicationRecord
  self.table_name = 'crm_agent_conversations'

  STATUSES = %w[IDLE RUNNING FAILED].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :crm_customer, class_name: 'Crm::Customer', optional: true
  has_many :messages, -> { order(:id) }, class_name: 'Crm::AgentMessage',
                                         foreign_key: :conversation_id, dependent: :destroy, inverse_of: :conversation

  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

  def running? = status == 'RUNNING'

  # 标题取第一句问话的前 24 个字——用户不会去给对话起名字。
  def title_from_first_question
    messages.find { |m| m.role == 'user' }&.content.to_s.strip[0, 24].presence || '新对话'
  end
end
