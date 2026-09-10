json.id resource.id
json.entry_date resource.entry_date
json.direction resource.direction
json.amount resource.amount
json.subject resource.subject
json.channel resource.channel
json.category resource.category
json.handler_id resource.handler_id
json.handler_name resource.handler&.name
json.remark resource.remark
json.oa_approval_request_id resource.oa_approval_request_id
json.created_by_name resource.created_by&.name
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
