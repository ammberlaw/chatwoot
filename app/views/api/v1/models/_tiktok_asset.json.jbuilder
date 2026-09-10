json.id resource.id
json.department_id resource.department_id
json.department_name resource.department&.name
json.name resource.name
json.code resource.code
json.category resource.category
json.purchased_on resource.purchased_on
json.amount resource.amount
json.holder_id resource.holder_id
json.holder_name resource.holder&.name
json.location resource.location
json.status resource.status
json.status_label resource.status_label
json.remark resource.remark
json.creator_name resource.creator&.name
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
