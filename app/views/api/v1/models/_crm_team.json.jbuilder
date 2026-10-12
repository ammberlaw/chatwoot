json.id resource.id
json.name resource.name
json.description resource.description
json.team_lead_id resource.team_lead_id
# 只出在职成员：已停用（离职）的人 crm_team_id 还在，但不该再出现在花名册和下拉里。
json.member_ids resource.active_account_users.pluck(:user_id)
json.members do
  json.array! resource.active_members do |user|
    json.id user.id
    json.name user.crm_display_name
  end
end
