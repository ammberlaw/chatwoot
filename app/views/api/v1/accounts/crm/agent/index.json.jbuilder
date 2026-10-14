json.payload do
  json.array! @conversations do |conversation|
    json.id conversation.id
    json.title conversation.title.presence || conversation.title_from_first_question
    json.status conversation.status
    json.crm_customer_name conversation.crm_customer&.name
    json.updated_at conversation.updated_at
  end
end
