json.meta do
  json.count @materials_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @materials do |material|
    json.partial! 'api/v1/models/mes_material', formats: [:json], resource: material
  end
end
