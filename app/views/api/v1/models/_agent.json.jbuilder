json.id resource.id
# could be nil for a deleted agent hence the safe operator before account id
json.account_id Current.account&.id
json.availability_status resource.availability_status
json.auto_offline resource.auto_offline
json.confirmed resource.confirmed?
json.email resource.email
json.provider resource.provider
json.available_name resource.available_name
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.name resource.name
json.role resource.role
json.crm_role resource.current_account_user&.crm_role
# 账号停用（离职）：各处「选人」据此剔掉——这个列表是全体用户，不带标记的话
# 离职的人照样出现在建群、@提及、共享等候选里（用户反馈「万婷到处出现」）。
# 只给标记不直接过滤：历史消息/记录里还要显示他们的名字。
json.deactivated resource.current_account_user&.deactivated_at.present? || false
json.thumbnail resource.avatar_url
json.custom_role_id resource.current_account_user&.custom_role_id if ChatwootApp.enterprise?
