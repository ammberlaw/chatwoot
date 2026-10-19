json.id resource.id
json.status resource.status
json.owner_id resource.owner_id
json.owner_name resource.owner&.name
# event_name 也在 EDITABLE_FIELDS 里，跟着一起吐，不用单列
Crm::BusinessCard::EDITABLE_FIELDS.each { |f| json.set! f, resource.public_send(f) }
json.raw_text resource.raw_text
json.parse_error resource.parse_error
json.parsed_at resource.parsed_at
json.created_at resource.created_at
json.crm_customer_id resource.crm_customer_id
json.customer_name resource.crm_customer&.name
# 照片走 ActiveStorage 的代理地址：COS 的直链是带签名的，存进前端缓存一会儿就过期。
json.image_url resource.image.attached? ? url_for(resource.image) : nil
