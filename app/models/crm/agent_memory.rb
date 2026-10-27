# AI 助手记住的一条关于「你」的事：偏好、口径、纠正。
#
# 不是知识库：公司怎么运作写在提示词和功能地图里，这里只放「这个人怎么用」。
# == Schema Information
#
# Table name: crm_agent_memories
#
#  id                     :bigint           not null, primary key
#  content                :text             not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  source_conversation_id :bigint
#  user_id                :bigint           not null
#
# Indexes
#
#  index_crm_agent_memories_on_account_user_time  (account_id,user_id,created_at)
#
class Crm::AgentMemory < ApplicationRecord
  self.table_name = 'crm_agent_memories'

  belongs_to :account
  belongs_to :user

  validates :content, presence: true, length: { maximum: 200 }

  # 一个人最多留这么多条。超了删最旧的——
  # 不设上限的话，提示词会被几百条琐碎偏好撑爆，模型反而抓不住重点。
  MAX_PER_USER = 40

  scope :for_user, ->(account_id, user_id) { where(account_id: account_id, user_id: user_id).order(created_at: :desc) }

  def self.remember!(account:, user_id:, content:, conversation_id: nil)
    text = content.to_s.strip.truncate(200)
    return nil if text.blank?

    # 同一句话不重复记：模型被反复纠正同一点时会反复想记。
    existing = for_user(account.id, user_id).find { |m| m.content.casecmp?(text) }
    return existing if existing

    row = create!(account_id: account.id, user_id: user_id, content: text, source_conversation_id: conversation_id)
    prune!(account.id, user_id)
    row
  end

  def self.prune!(account_id, user_id)
    extra = for_user(account_id, user_id).offset(MAX_PER_USER).pluck(:id)
    where(id: extra).delete_all if extra.any?
  end
end
