# 邮件 AI 助手设置（每账户一行）：管理员在 CRM 后台配置 DeepSeek（或其它 OpenAI 兼容）API key、
# 模型、可选自定义端点。Crm::EmailAiService 运行时读取；无记录/未填时降级读环境变量。
# == Schema Information
#
# Table name: crm_ai_settings
#
#  id                       :bigint           not null, primary key
#  agent_user_ids           :bigint           default([]), not null, is an Array
#  api_base                 :string
#  api_key                  :text
#  apollo_api_key           :text
#  auto_draft_reply_enabled :boolean          default(FALSE), not null
#  auto_draft_user_ids      :bigint           default([]), not null, is an Array
#  inquiry_triage_enabled   :boolean          default(FALSE), not null
#  model                    :string           default("deepseek-chat"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  index_crm_ai_settings_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Crm::AiSetting < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true

  def self.for_account(account)
    find_by(account_id: account.id) || new(account: account)
  end

  # 谁能用 CRM 的 AI 助手。名单空＝只有管理员/副管能用（先小范围试，用户定的）。
  # 管理员恒可用：名单是她自己配的，配空了把自己也关在外面说不过去。
  def self.agent_allowed?(account, account_user)
    return false if account_user.blank?
    return true if account_user.administrator? || account_user.crm_deputy_admin?

    for_account(account).agent_user_ids.to_a.include?(account_user.user_id)
  end
end
