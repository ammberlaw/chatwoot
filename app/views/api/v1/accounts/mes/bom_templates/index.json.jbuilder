json.meta do
  json.hidden_no_line @hidden_no_line
end

json.payload do
  json.array! @templates do |template|
    json.partial! 'api/v1/models/mes_bom_template', formats: [:json], resource: template
  end
end
