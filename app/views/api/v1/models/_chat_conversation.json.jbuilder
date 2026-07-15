json.id resource.id
json.kind resource.kind
json.name resource.display_name_for(current_user.id)
json.creator_id resource.creator_id
json.announcement resource.announcement
json.last_message_at resource.last_message_at
json.unread_count resource.unread_count_for(current_user.id)
json.participant_count resource.participants.size

peer = resource.peer_participant(current_user.id)
json.peer_id peer&.user_id
json.peer_name peer&.user&.name

last = resource.messages.order(id: :desc).first
json.last_message do
  if last
    json.content last.content
    json.sender_id last.sender_id
    json.created_at last.created_at
  else
    json.content nil
  end
end
