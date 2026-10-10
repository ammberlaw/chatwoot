json.payload do
  json.array! @missing do |row|
    json.sku row[:sku]
    json.crm_product_id row[:crm_product_id]
    json.name row[:name]
    json.specification row[:specification]
    json.unit row[:unit]
    json.bom_count row[:bom_count]
    json.total_qty row[:total_qty]
  end
end
json.meta do
  json.count @missing.size
end
