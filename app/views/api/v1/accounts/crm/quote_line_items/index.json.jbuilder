json.payload do
  json.array! @line_items do |item|
    json.partial! 'api/v1/models/crm_quote_line_item', formats: [:json], resource: item
  end
end
