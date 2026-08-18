json.payload do
  json.array! @distributions do |d|
    json.id d.id
    json.to_user_id d.to_user_id
    json.to_user_name d.to_user&.crm_display_name
    json.from_user_id d.from_user_id
    json.from_user_name d.from_user&.crm_display_name
    json.note d.note
    json.read_at d.read_at
    json.created_at d.created_at
  end
end
