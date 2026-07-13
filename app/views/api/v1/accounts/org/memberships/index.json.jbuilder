json.payload do
  json.array! @memberships do |membership|
    json.partial! 'api/v1/models/org_membership', formats: [:json], resource: membership
  end
end
