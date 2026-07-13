json.meta do
  json.count @requests.total_count
  json.current_page @requests.current_page
end
json.payload do
  json.array! @requests do |request|
    json.partial! 'api/v1/models/oa_approval_request', formats: [:json], resource: request
  end
end
