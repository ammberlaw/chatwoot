# api_key 不回显明文：只告知是否已配置 + 尾 4 位，供前端显示「已配置 ••••abcd」。
key = @setting.api_key.to_s
json.configured key.present?
json.key_hint key.present? ? key[-4..] : nil
json.model @setting.model
json.api_base @setting.api_base

# Apollo 企业库 key 同样脱敏，只回是否已配 + 尾 4 位。
apollo = @setting.apollo_api_key.to_s
json.apollo_configured apollo.present?
json.apollo_key_hint apollo.present? ? apollo[-4..] : nil

# 谁能用 CRM 的 AI 助手。管理员/副管恒可用，不在这张名单里也行。
json.agent_user_ids @setting.agent_user_ids.to_a

# 新询盘自动初筛开关（Crm::InquiryTriageJob）。默认关：它会自动调模型花钱。
json.inquiry_triage_enabled @setting.inquiry_triage_enabled

# 本月用量：开了自动初筛之后它会自己跑、自己花钱，管理员得看得到花了多少。
json.usage @usage || {}
