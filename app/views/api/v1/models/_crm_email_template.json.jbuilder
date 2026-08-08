json.id resource.id
json.name resource.name
json.category resource.category
json.subject_template resource.subject_template
json.body resource.body
json.description resource.description
json.files(resource.files) do |f|
  json.id f.id
  json.filename f.filename.to_s
  json.byte_size f.byte_size
  json.url url_for(f)
end
