json.meta do
  json.count @stock_entries_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @stock_entries do |stock_entry|
    json.partial! 'api/v1/models/mes_stock_entry', formats: [:json], resource: stock_entry
  end
end
