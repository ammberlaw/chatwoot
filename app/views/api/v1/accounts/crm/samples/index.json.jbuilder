json.payload do
  json.array! @samples do |sample|
    json.partial! 'api/v1/accounts/crm/samples/sample', sample: sample
  end
end
