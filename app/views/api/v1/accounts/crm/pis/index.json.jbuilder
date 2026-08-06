json.meta do
  json.count @pis_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @pis do |pi|
    json.partial! 'api/v1/models/crm_pi', formats: [:json], resource: pi
  end
end
