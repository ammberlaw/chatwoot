json.id resource.id
json.department_id resource.department_id
json.department_name resource.department&.name
json.shop_id resource.shop_id
json.shop_name resource.shop&.name
json.expense_date resource.expense_date
json.category resource.category
json.subject resource.subject
json.amount resource.amount
json.currency resource.currency
json.amount_cny resource.amount_cny
json.fx_rate resource.fx_rate
json.remark resource.remark
json.creator_name resource.creator&.name
json.files resource.files.map { |f| { id: f.id, filename: f.filename.to_s, url: url_for(f) } }
