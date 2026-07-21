json.meta do
  json.count @production_records_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @production_records do |record|
    json.partial! 'api/v1/models/mes_production_record', formats: [:json], resource: record
  end
end
