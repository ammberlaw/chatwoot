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
  # 用户可以直接给助手发图或发文件：展会上拍的规格表、手写询价、客户发来的实物照，
  # 以及客户直接丢过来的 PI / 报价表 / 规格书（PDF、Excel、Word、PPT）。
  # 以前只能走邮件附件（read_attachment 要 email_id），手机拍的照片和刚收到的文件没有入口。
  #
  # 一条消息一个附件：图走视觉模型读成文字（Crm::Agent::VisionReader），
  # 文档走 Crm::DocumentText 抽正文——agent 手里的工具全是查库的，
  # 没有一个能看图或读文件，不先读成文字这个附件对它就是不存在的。
  has_one_attached :attachment

  self.table_name = 'crm_agent_messages'

  ROLES = %w[user assistant tool].freeze

  belongs_to :account
  belongs_to :conversation, class_name: 'Crm::AgentConversation', inverse_of: :messages

  validates :role, inclusion: { in: ROLES }

  before_validation { self.account_id ||= conversation&.account_id }
end
