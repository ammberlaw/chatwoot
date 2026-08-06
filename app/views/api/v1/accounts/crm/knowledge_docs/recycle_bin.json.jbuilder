json.payload do
  json.array! @docs do |doc|
    json.id doc.id
    json.name doc.name
    json.scope doc.scope
    json.library doc.library
    json.category doc.category
    json.owner_name doc.owner&.crm_display_name
    json.discarded_by_name doc.discarded_by&.crm_display_name
    json.discarded_at doc.discarded_at
  end
end
