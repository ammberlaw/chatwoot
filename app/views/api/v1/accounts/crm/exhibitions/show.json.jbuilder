json.partial! 'api/v1/models/crm_exhibition', formats: [:json], resource: @exhibition

json.invites do
  json.array! @invites do |invite|
    json.partial! 'api/v1/models/crm_exhibition_invite', formats: [:json], resource: invite
  end
end
