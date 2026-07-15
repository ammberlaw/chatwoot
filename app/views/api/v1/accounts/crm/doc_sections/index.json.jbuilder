json.payload do
  json.array! @sections do |section|
    json.id section.id
    json.name section.name
    json.department_ids section.department_ids
    json.is_default Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)
  end
end
