json.payload do
  json.array! @campaigns do |campaign|
    json.partial! 'api/v1/accounts/crm/lead_campaigns/lead_campaign', campaign: campaign
  end
end

# Apollo 解锁额度（见 Crm::ApolloQuota）。limit 为 null 表示没设上限。
json.apollo_quota do
  json.user_limit @quota.user_limit
  json.user_used @quota.user_used
  json.user_left @quota.user_left
  json.account_left @quota.account_left
end
