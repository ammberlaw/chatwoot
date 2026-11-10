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
json.auto_draft_reply_enabled @setting.auto_draft_reply_enabled
json.auto_draft_user_ids @setting.auto_draft_user_ids

# 本月用量：开了自动初筛之后它会自己跑、自己花钱，管理员得看得到花了多少。
json.usage @usage || {}

# Apollo 积分额度。Apollo 自己没有查余额的接口（usage_stats 404），用量只能我们记。
# 能扣积分的只有「解锁联系方式」，所以额度就卡在那一步（见 Crm::ApolloQuota）。
json.apollo_monthly_limit @setting.apollo_monthly_limit
json.apollo_user_limit @setting.apollo_user_limit
json.apollo_user_limits @setting.apollo_user_limits
json.apollo_usage do
  json.unlocked_this_month @apollo.used
  # 背调家数。2026-11-10 对账实证：只有官网抓不到时才走企业库扣 1 credit，
  # 官网抓得到的走 DeepSeek 一分不花——所以这个数是上限，不是实际花费。
  json.bg_checks_this_month @apollo.bg_checks_this_month
  # 按人列：谁解了多少、领取时抓了多少联系人、手动点了多少次背调，各人额度多少。
  # 原来只给 { user_id => 解锁数 }，页面上连名字都没有，管理员得自己对 id。
  json.by_user @apollo.by_user_rows
end

# 公司级默认初筛条件：新建拓客任务时自动带上（见 LeadCampaignsController#create）。
json.lead_default_criteria @setting.lead_default_criteria

# 本月 AI 用量，按用途分。只给 token 数不折钱——单价随模型变，折算出来很快就过期。
json.ai_usage Crm::AiCall.month_summary(Current.account)
