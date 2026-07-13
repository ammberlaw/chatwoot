json.payload do
  json.array! @messages do |message|
    json.partial! 'api/v1/models/chat_message', formats: [:json], resource: message
  end
end
