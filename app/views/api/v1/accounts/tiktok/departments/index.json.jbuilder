json.payload do
  json.array! @departments do |department|
    json.partial! 'api/v1/models/tiktok_department', formats: [:json], resource: department
  end
end
