json.id resource.id
json.title resource.title
json.starts_at resource.starts_at
json.ends_at resource.ends_at
json.all_day resource.all_day
json.location resource.location
json.note resource.note
json.color resource.color
json.recurrence resource.recurrence
json.recurrence_until resource.recurrence_until
json.kind resource.kind
json.customer_id resource.customer_id
json.customer_name resource.customer&.name if resource.customer_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.crm_display_name
json.is_owner resource.owner_id == current_user.id
json.participant_ids resource.participant_users.map(&:id)
json.participant_names resource.participant_users.map(&:crm_display_name)
