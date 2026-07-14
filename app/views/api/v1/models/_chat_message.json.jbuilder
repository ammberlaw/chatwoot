json.id resource.id
json.content resource.content
json.sender_id resource.sender_id
json.sender_name resource.sender&.name
json.read_by resource.read_by_count
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
