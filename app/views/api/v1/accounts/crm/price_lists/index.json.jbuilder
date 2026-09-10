json.can_manage @can_manage
json.product_lines @product_lines
json.payload do
  json.array! @price_lists do |list|
    json.partial! 'api/v1/models/crm_price_list', formats: [:json], resource: list
  end
end
