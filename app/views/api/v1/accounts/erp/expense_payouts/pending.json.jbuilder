json.payload do
  json.array! @requests do |request|
    suggestion = @suggestions[request.id] || {}
    json.id request.id
    json.title request.title
    json.applicant_name request.applicant&.name.presence || request.applicant&.crm_name
    json.applicant_id request.applicant_id
    json.department_name request.department&.name
    json.template_name request.template&.name
    json.submitted_at request.submitted_at
    json.approved_at request.updated_at
    json.form_data request.form_data
    json.amount_micros suggestion[:amount_micros]
    json.category suggestion[:category]
    json.suggested_expense_ledger_account_id suggestion[:expense_ledger_account_id]
  end
end
