json.meta do
  json.count @quotes_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @quotes do |quote|
    json.partial! 'api/v1/models/crm_quote', formats: [:json], resource: quote
  end
end
