json.payload do
  json.array! @conversations do |conversation|
    json.partial! 'api/v1/models/chat_conversation', formats: [:json], resource: conversation
  end
end
