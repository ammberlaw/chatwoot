json.id resource.id
json.name resource.name
json.leader_id resource.leader_id
json.leader_name resource.leader&.name
json.member_ids resource.account_users.map(&:user_id)
json.members resource.members do |user|
  json.id user.id
  json.name user.name
end
json.shop_ids resource.shops.map(&:id)
json.shop_names resource.shops.map(&:name)
