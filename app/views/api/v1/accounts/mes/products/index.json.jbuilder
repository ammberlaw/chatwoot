json.meta do
  json.count @products_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @products do |product|
    json.partial! 'api/v1/models/crm_product', formats: [:json], resource: product
  end
end
