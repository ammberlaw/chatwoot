json.id resource.id
json.name resource.name
json.description resource.description
json.icon resource.icon
json.active resource.active
json.position resource.position
json.form_fields resource.form_fields
json.attendance_kind resource.attendance_kind
json.flow resource.flow
json.cc_user_ids resource.cc_user_ids
json.cc_names User.where(id: resource.cc_user_ids).pluck(:name)
