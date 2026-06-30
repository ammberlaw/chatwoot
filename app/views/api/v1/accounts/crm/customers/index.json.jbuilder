json.meta do
  json.count @customers_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @customers do |customer|
    json.partial! 'api/v1/models/crm_customer', formats: [:json], resource: customer
  end
end
