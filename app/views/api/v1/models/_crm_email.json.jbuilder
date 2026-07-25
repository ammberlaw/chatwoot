json.id resource.id
json.subject resource.subject
json.folder resource.folder
json.is_read resource.is_read
json.is_starred resource.is_starred
json.from_address resource.from_address
json.to_address resource.to_address
json.cc_address resource.cc_address
json.bcc_address resource.bcc_address
json.email_date resource.email_date
json.body resource.body
json.body_html resource.body_html
json.send_status resource.send_status
json.send_error resource.send_error
json.scheduled_at resource.scheduled_at
json.reply_latency_hours resource.reply_latency_hours
json.tracked resource.tracking_token.present?
json.open_count resource.open_count
json.first_opened_at resource.first_opened_at
json.last_opened_at resource.last_opened_at
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
json.contact_id resource.contact_id
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
visible_files = resource.files.reject { |f| f.blob.metadata['inline'] }
json.files(visible_files) do |f|
  json.id f.id
  json.filename f.filename.to_s
  json.byte_size f.byte_size
  json.url url_for(f)
end
json.created_at resource.created_at
