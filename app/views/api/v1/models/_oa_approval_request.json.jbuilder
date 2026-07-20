json.id resource.id
json.title resource.title
json.status resource.status
json.current_position resource.current_position
json.template_id resource.template_id
json.template_name resource.template&.name
json.template_icon resource.template&.icon
json.applicant_id resource.applicant_id
json.applicant_name resource.applicant&.name
json.cc_user_ids resource.cc_user_ids
json.cc_names User.where(id: resource.cc_user_ids).pluck(:name)
json.submitted_at resource.submitted_at
json.created_at resource.created_at
