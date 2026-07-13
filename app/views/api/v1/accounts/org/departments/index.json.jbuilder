json.payload do
  json.array! @departments do |department|
    json.partial! 'api/v1/models/org_department', formats: [:json], resource: department
  end
end
