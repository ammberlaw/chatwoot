json.partial! 'api/v1/models/oa_approval_request', formats: [:json], resource: @request
json.form_data @request.form_data
json.form_fields @request.template&.form_fields
json.department_id @request.department_id
json.department_name @request.department&.name
json.files @request.files.map { |f| { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f) } }
json.can_act @request.pending? && @request.current_step&.approver_id == current_user.id && @request.current_step&.status == 'pending'
json.is_applicant @request.applicant_id == current_user.id
json.steps do
  json.array! @request.steps do |step|
    json.id step.id
    json.position step.position
    json.status step.status
    json.approver_id step.approver_id
    json.approver_name step.approver&.name
    json.comment step.comment
    json.acted_at step.acted_at
    json.is_current step.position == @request.current_position && @request.pending?
  end
end
