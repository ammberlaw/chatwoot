json.payload do
  json.array! @items do |item|
    json.partial! 'api/v1/models/crm_option_item', formats: [:json], resource: item
  end
end
