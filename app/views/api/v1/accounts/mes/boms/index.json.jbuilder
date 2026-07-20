json.meta do
  json.count @boms_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @boms do |bom|
    json.partial! 'api/v1/models/mes_bom', formats: [:json], resource: bom
  end
end
