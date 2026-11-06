json.(report, :id, :status, :body, :subject_no, :subject_type, :action_type, :resolution)
# 报的人取提交当时存下来的名字：人离职改名后，通知里和这里要对得上。
json.reporter_name report.reporter_name
json.reporter_role report.context.dig('reporter', 'crm_role')
json.reporter_admin report.context.dig('reporter', 'admin')
json.diagnosis report.diagnosis_summary
json.diagnosis_error report.context['diagnosis_error']
json.resolved_by_name report.resolved_by&.name
json.resolved_at report.resolved_at
json.created_at report.created_at
