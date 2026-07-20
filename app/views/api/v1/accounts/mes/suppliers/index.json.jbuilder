json.meta do
  json.count @suppliers_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @suppliers do |supplier|
    json.partial! 'api/v1/models/mes_supplier', formats: [:json], resource: supplier
  end
end
