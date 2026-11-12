json.id resource.id
json.name resource.name
json.parent_id resource.parent_id
json.position resource.position
json.leader_id resource.leader_id
leader = resource.account.account_users.active_members.find_by(user_id: resource.leader_id)
json.leader_name leader&.user&.crm_display_name
json.leader_inactive resource.leader_id.present? && leader.nil?
json.member_count resource.active_member_count
json.archived_at resource.archived_at
