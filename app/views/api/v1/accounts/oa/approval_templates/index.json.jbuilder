json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/models/oa_approval_template', formats: [:json], resource: template
  end
end
