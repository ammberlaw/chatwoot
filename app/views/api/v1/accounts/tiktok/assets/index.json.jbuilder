json.meta do
  json.editable_department_ids(@editable_department_ids == :all ? 'all' : @editable_department_ids)
  json.total_amount @assets.sum(&:amount)
end

json.payload do
  json.array! @assets do |asset|
    json.partial! 'api/v1/models/tiktok_asset', formats: [:json], resource: asset
  end
end
