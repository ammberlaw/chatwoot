json.id resource.id
json.name resource.name
json.customer_code resource.customer_code
json.account_owner_id resource.account_owner_id
json.account_owner_name resource.account_owner&.name

json.trade_country resource.trade_country
json.trade_region resource.trade_region
json.trade_city resource.trade_city

json.industry resource.industry
json.customer_level resource.customer_level
json.source_channel resource.source_channel
json.currency_preference resource.currency_preference
json.customer_status resource.customer_status
json.customer_group resource.customer_group
json.product_group resource.product_group
json.risk_level resource.risk_level

json.last_follow_up_at resource.last_follow_up_at
json.next_follow_up_at resource.next_follow_up_at
json.is_in_public_pool resource.is_in_public_pool
json.public_pool_at resource.public_pool_at

json.primary_contact_name resource.primary_contact_name
json.contact_job_title resource.contact_job_title
json.contact_email resource.contact_email
json.contact_phone resource.contact_phone
json.whats_app resource.whats_app
json.wechat resource.wechat
json.contact_preference resource.contact_preference
json.customer_remark resource.customer_remark

json.deal_total_amount_micros resource.deal_total_amount_micros
json.deal_order_count resource.deal_order_count
json.first_deal_at resource.first_deal_at
json.last_deal_at resource.last_deal_at

json.info_completeness_score resource.info_completeness_score
json.completeness_grade resource.completeness_grade

json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, byte_size: f.byte_size, url: url_for(f) } }

json.created_at resource.created_at.to_i
json.updated_at resource.updated_at.to_i
