json.payload do
  json.array! @material_prices do |material_price|
    json.partial! 'api/v1/models/mes_material_price', resource: material_price,
                                                      last_purchase: @purchase_marks[material_price.crm_product_id]
  end
end
json.meta do
  json.count @material_prices_count
end
