json.meta do
  json.count @cards_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @cards do |card|
    json.partial! 'api/v1/models/crm_business_card', formats: [:json], resource: card
  end
end
