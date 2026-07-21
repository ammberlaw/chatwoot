json.meta do
  json.count @inspections_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @inspections do |inspection|
    json.partial! 'api/v1/models/mes_inspection', formats: [:json], resource: inspection
  end
end
