# 邮件 AI 助手设置（每账户一行）：管理员在 CRM 后台配置 DeepSeek（或其它 OpenAI 兼容）API key、
# 模型、可选自定义端点。Crm::EmailAiService 运行时读取；无记录/未填时降级读环境变量。
# == Schema Information
#
# Table name: crm_ai_settings
#
#  id             :bigint           not null, primary key
#  api_base       :string
#  api_key        :text
#  apollo_api_key :text
#  model          :string           default("deepseek-chat"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
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
end
