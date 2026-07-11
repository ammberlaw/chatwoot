json.meta do
  json.count @opportunities_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @opportunities do |opportunity|
    json.partial! 'api/v1/models/crm_opportunity', formats: [:json], resource: opportunity
  end
end
