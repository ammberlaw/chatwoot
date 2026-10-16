json.meta do
  json.count @returns_count
  json.current_page params[:page] || 1
end
json.payload do
  json.array! @returns do |record|
    json.partial! 'api/v1/models/mes_supplier_return', formats: [:json], resource: record
  end
end
