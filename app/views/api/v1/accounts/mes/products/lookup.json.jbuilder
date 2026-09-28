# 批量按编码查档案：按送进来的顺序回，匹配不上的 product 为 null，前端据此标红。
json.payload do
  json.array! @lookup_rows do |row|
    json.code row[:code]
    if row[:product]
      json.product do
        json.partial! 'api/v1/models/crm_product', formats: [:json], resource: row[:product]
      end
    else
      json.product nil
    end
  end
end
