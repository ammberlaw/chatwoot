json.id resource.id
json.content resource.content
json.sender_id resource.sender_id
json.sender_name resource.sender&.name
# 发送人头像由后端给：「系统通知」不是坐席，前端的坐席表里查不到它的头像。
json.sender_avatar_url resource.sender&.avatar_url.presence
json.read_by resource.read_by_count
json.mentioned_ids resource.mentioned_ids
if resource.reply_to_id.present? && resource.reply_to
  json.reply_to do
    json.id resource.reply_to.id
    json.sender_name resource.reply_to.sender&.name
    json.content resource.reply_to.content.to_s.truncate(60)
    json.is_image resource.reply_to.files.any? { |f| f.content_type.to_s.start_with?('image/') }
  end
end
if resource.ref_type.present?
  json.ref do
    json.type resource.ref_type
    json.id resource.ref_id
    json.snapshot resource.ref_snapshot
  end
end
json.files resource.files.map { |f|
  {
    id: f.id,
    filename: f.filename.to_s,
    url: url_for(f),
    content_type: f.content_type,
    byte_size: f.byte_size,
    is_image: f.content_type.to_s.start_with?('image/')
  }
}
json.created_at resource.created_at
