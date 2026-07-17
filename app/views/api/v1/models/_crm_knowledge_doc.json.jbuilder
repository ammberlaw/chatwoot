json.id resource.id
json.name resource.name
json.category resource.category
json.summary resource.summary
json.scope resource.scope
json.library resource.library
json.section_id resource.section_id
json.body resource.body
json.owner_id resource.owner_id
json.manager_ids resource.manager_ids
json.manager_names User.where(id: resource.manager_ids).pluck(:name)
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
json.updated_at resource.updated_at
