json.partial! 'api/v1/models/chat_conversation', formats: [:json], resource: @conversation
json.participants do
  json.array! @conversation.participants.includes(:user) do |part|
    json.user_id part.user_id
    json.name part.user&.name
    json.last_read_message_id part.last_read_message_id
  end
end
