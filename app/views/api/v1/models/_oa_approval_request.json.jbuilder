json.id resource.id
json.title resource.title
json.status resource.status
json.current_position resource.current_position
json.template_id resource.template_id
json.template_name resource.definition.name
json.template_icon resource.template&.icon
json.applicant_id resource.applicant_id
json.applicant_name resource.applicant&.name
json.applicant_avatar_url resource.applicant&.avatar_url
json.cc_user_ids resource.cc_user_ids
json.cc_names resource.account.users.where(id: resource.cc_user_ids).map(&:crm_display_name)
json.revokable resource.revocable?
json.revokes_request_id resource.revokes_request_id
json.submitted_at resource.submitted_at
json.created_at resource.created_at

json.template_revision resource.definition.revision
json.legacy_snapshot !!resource.definition.data['legacy']
json.source_request_id resource.source_request_id
json.integration_result resource.integration_result
json.overdue resource.overdue?
json.waiting_since resource.pending? ? (resource.current_step&.assigned_at || resource.submitted_at) : nil
json.waiting_estimated resource.pending? && resource.current_step&.assigned_at.nil?
json.last_reminded_at resource.last_reminded_at
