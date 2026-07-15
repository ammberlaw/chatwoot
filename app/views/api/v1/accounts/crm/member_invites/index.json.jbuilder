json.payload do
  json.array! @invites do |invite|
    json.partial! 'invite', formats: [:json], invite: invite
  end
end
