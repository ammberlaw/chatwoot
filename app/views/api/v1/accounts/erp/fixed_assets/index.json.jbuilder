json.meta do
  json.original_micros @summary[:original_micros]
  json.accumulated_micros @summary[:accumulated_micros]
  json.net_micros @summary[:original_micros].to_i - @summary[:accumulated_micros].to_i
end
json.payload do
  json.array! @assets do |asset|
    json.partial! 'api/v1/models/erp_fixed_asset', formats: [:json], resource: asset
  end
end
