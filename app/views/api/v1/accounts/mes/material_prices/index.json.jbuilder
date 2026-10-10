json.payload do
  json.array! @material_prices do |material_price|
    json.partial! 'api/v1/models/mes_material_price', resource: material_price
  end
end
json.meta do
  json.count @material_prices_count
end
