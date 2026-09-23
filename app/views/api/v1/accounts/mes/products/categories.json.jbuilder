json.payload do
  json.array! @category_tree do |product_line, categories|
    json.product_line product_line
    json.count categories.sum { |c| c[:count] }
    json.categories categories
  end
end
