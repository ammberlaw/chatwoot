ret = resource.active_return
json.returned ret.present?
json.returnable resource.returnable?
json.return_reason ret&.reason
json.returned_by_name ret&.returned_by&.name
json.returned_at ret&.created_at
