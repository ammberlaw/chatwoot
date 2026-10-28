json.id conversation.id
json.title conversation.title.presence || conversation.title_from_first_question
json.status conversation.status
json.last_error conversation.last_error
json.crm_customer_id conversation.crm_customer_id
json.crm_customer_name conversation.crm_customer&.name
json.updated_at conversation.updated_at
json.messages conversation.messages do |message|
  json.id message.id
  json.role message.role
  json.content message.content
  json.meta message.meta
  json.created_at message.created_at
  # 发出去的图/文件也要在记录里看得见：不回显的话发完就只剩一句话，
  # 翻回去根本看不出当时甩的是哪张图、哪份 PI。
  if message.attachment.attached?
    json.attachment do
      json.name message.attachment.filename.to_s
      json.content_type message.attachment.content_type
      json.url url_for(message.attachment)
    end
  end
end
