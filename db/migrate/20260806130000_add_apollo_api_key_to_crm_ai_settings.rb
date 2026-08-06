class AddApolloApiKeyToCrmAiSettings < ActiveRecord::Migration[7.1]
  def change
    # Apollo.io 企业数据库 API Key：客户 AI 背调按域名补全公司概况 + 联系人。
    # 与 DeepSeek 的 api_key 共用同一张账户级设置表，管理员在「AI 配置」页填写。
    add_column :crm_ai_settings, :apollo_api_key, :text
  end
end
