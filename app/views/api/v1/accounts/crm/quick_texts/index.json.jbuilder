json.payload do
  json.array! @quick_texts do |qt|
    json.partial! 'api/v1/models/crm_quick_text', formats: [:json], resource: qt
  end
end
