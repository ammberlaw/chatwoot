json.id resource.id
json.name resource.name
json.description resource.description
json.team_lead_id resource.team_lead_id
json.member_ids resource.account_users.pluck(:user_id)
json.members do
  json.array! resource.members do |user|
    json.id user.id
    json.name user.name
  end
end
