# AI 助手记住的一条关于「你」的事：偏好、口径、纠正。
#
# 不是知识库：公司怎么运作写在提示词和功能地图里，这里只放「这个人怎么用」。
# == Schema Information
#
# Table name: crm_agent_memories
#
#  id                     :bigint           not null, primary key
#  content                :text             not null
#  scope                  :string           default("USER"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  source_conversation_id :bigint
#  user_id                :bigint           not null
#
# Indexes
#
#  index_crm_agent_memories_on_account_scope_time  (account_id,scope,created_at)
#  index_crm_agent_memories_on_account_user_time   (account_id,user_id,created_at)
#
class Crm::AgentMemory < ApplicationRecord
  self.table_name = 'crm_agent_memories'

  belongs_to :account
  belongs_to :user

  validates :content, presence: true, length: { maximum: 200 }

  # 一个人最多留这么多条。超了删最旧的——
  # 不设上限的话，提示词会被几百条琐碎偏好撑爆，模型反而抓不住重点。
  MAX_PER_USER = 40
  # 公司规矩是全员每轮都带的，更要克制：真正全公司通用的规矩没有几十条，
  # 放宽了就会有人把自己的习惯塞进来占所有人的提示词。
  MAX_PER_ACCOUNT = 20

  USER_SCOPE = 'USER'.freeze
  ACCOUNT_SCOPE = 'ACCOUNT'.freeze

  validates :scope, inclusion: { in: [USER_SCOPE, ACCOUNT_SCOPE] }

  scope :for_user, lambda { |account_id, user_id|
    where(account_id: account_id, user_id: user_id, scope: USER_SCOPE).order(created_at: :desc)
  }
  # 全公司的规矩，谁记的都算数。
  scope :for_account, lambda { |account_id|
    where(account_id: account_id, scope: ACCOUNT_SCOPE).order(created_at: :desc)
  }

  def account_wide? = scope == ACCOUNT_SCOPE

  def self.remember!(account:, user_id:, content:, conversation_id: nil, account_wide: false)
    text = content.to_s.strip.truncate(200)
    return nil if text.blank?

    kind = account_wide ? ACCOUNT_SCOPE : USER_SCOPE
    # 同一句话不重复记：模型被反复纠正同一点时会反复想记。
    # 两档分开查——同一句话既可以是我的习惯，也可以被管理员立成公司规矩。
    existing = rows_of(account.id, user_id, kind).find { |m| m.content.casecmp?(text) }
    return existing if existing

    row = create!(account_id: account.id, user_id: user_id, content: text,
                  source_conversation_id: conversation_id, scope: kind)
    prune!(account.id, user_id, kind)
    row
  end

  def self.rows_of(account_id, user_id, kind)
    kind == ACCOUNT_SCOPE ? for_account(account_id) : for_user(account_id, user_id)
  end

  def self.prune!(account_id, user_id, kind = USER_SCOPE)
    cap = kind == ACCOUNT_SCOPE ? MAX_PER_ACCOUNT : MAX_PER_USER
    extra = rows_of(account_id, user_id, kind).offset(cap).pluck(:id)
    where(id: extra).delete_all if extra.any?
  end
end
