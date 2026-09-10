json.payload do
  json.array! @apollo_results do |c|
    json.name c[:name]
    json.domain c[:domain]
    json.industry c[:industry]
    json.city c[:city]
    json.country c[:country]
    json.logo c[:logo]
  end
end
