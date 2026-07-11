json.meta do
  json.count @docs_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @docs do |doc|
    json.partial! 'api/v1/models/crm_knowledge_doc', formats: [:json], resource: doc
  end
end
