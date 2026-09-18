json.meta do
  json.count @count
  json.current_page params[:page] || 1
end
json.payload do
  json.array! @requests do |r|
    json.partial! 'api/v1/models/crm_quote_request', formats: [:json], resource: r
  end
end
