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
end
