json.payload do
  json.array! @teams do |team|
    json.partial! 'api/v1/models/crm_team', formats: [:json], resource: team
  end
end
