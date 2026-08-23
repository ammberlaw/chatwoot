json.id resource.id
json.name resource.name
json.category resource.category
json.category_id resource.category_id
json.summary resource.summary
json.scope resource.scope
json.library resource.library
json.section_id resource.section_id
json.body resource.body
json.owner_id resource.owner_id
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f), byte_size: f.byte_size } }
json.updated_at resource.updated_at
