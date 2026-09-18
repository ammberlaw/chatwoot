json.id resource.id
json.request_no resource.request_no
json.title resource.title
json.product_line resource.product_line
json.spec_template resource.spec_template
json.status resource.status
json.form_data resource.form_data
json.quantity resource.quantity
json.created_at resource.created_at

json.template_id resource.template_id
json.template_name resource.template&.name
json.form_fields resource.template&.form_fields || []

json.applicant_id resource.applicant_id
json.applicant_name resource.applicant&.crm_display_name
json.pricer_id resource.pricer_id
json.pricer_name resource.pricer&.crm_display_name
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name

json.quoted_price_micros resource.quoted_price_micros
json.quote_currency resource.quote_currency
json.valid_until resource.valid_until
json.pricer_note resource.pricer_note
json.quoted_at resource.quoted_at
json.quoted_by_name resource.quoted_by&.crm_display_name

json.transfers resource.transfers.order(:created_at).map { |t|
  { from: t.from_user&.crm_display_name, to: t.to_user&.crm_display_name,
    reason: t.reason, at: t.created_at }
}

json.files resource.files.map { |f|
  { id: f.id, filename: f.filename.to_s, url: url_for(f) }
}
