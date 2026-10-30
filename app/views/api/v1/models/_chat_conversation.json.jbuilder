json.id resource.id
json.kind resource.kind
json.name resource.display_name_for(current_user.id)
json.creator_id resource.creator_id
json.announcement resource.announcement
json.last_message_at resource.last_message_at
json.unread_count chat_visible_unread_count(resource)
json.participant_count resource.participants.size
# 群头像（单聊不用，头像取对方坐席的）。
json.avatar_url resource.kind == 'group' ? resource.avatar_url : nil

peer = resource.peer_participant(current_user.id)
json.peer_id peer&.user_id
json.peer_name peer&.user&.name
# 单聊头像从这里给，不靠前端的坐席表：「系统通知」这类账号不是坐席、不在 agents 列表里，
# 查不到头像就只剩首字母圆底。
json.peer_avatar_url peer&.user&.avatar_url.presence
# 「系统通知」是机器人不是人：列表里永远置顶，也不该有在线/离线状态。
json.system_notice resource.kind != 'group' && peer&.user_id == Crm::SystemUser.for(Current.account).id

last = chat_visible_messages(resource).order(id: :desc).first
json.notice_view mobile_notice_view? ? 'todo_separate' : 'all'
json.last_message_at last&.created_at if mobile_notice_view?
json.last_message do
  if last
    json.id last.id
    json.ref last.ref_type.present? ? { type: last.ref_type, id: last.ref_id, snapshot: last.ref_snapshot } : nil
    json.content last.content
    json.sender_id last.sender_id
    json.created_at last.created_at
  else
    json.content nil
  end
end
