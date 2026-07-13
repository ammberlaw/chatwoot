json.payload do
  json.array! @categories do |category|
    json.partial! 'api/v1/models/crm_knowledge_category', formats: [:json], resource: category
  end
end
