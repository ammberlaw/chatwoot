json.payload do
  json.array! @shops do |shop|
    json.partial! 'api/v1/models/tiktok_shop', formats: [:json], resource: shop
  end
end
