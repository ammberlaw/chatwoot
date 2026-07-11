json.id resource.id
json.name resource.name
json.description resource.description
json.team_lead_id resource.team_lead_id
json.member_ids resource.account_users.pluck(:user_id)
