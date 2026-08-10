json.payload do
  json.array! @records do |record|
    json.partial! 'api/v1/models/tiktok_sales_record', formats: [:json], resource: record
  end
end
