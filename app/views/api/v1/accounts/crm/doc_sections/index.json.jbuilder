json.payload do
  json.array! @sections do |section|
    json.id section.id
    json.name section.name
    json.department_ids section.department_ids
    json.manager_ids section.manager_ids
    json.manager_names User.where(id: section.manager_ids).pluck(:name)
    json.is_default Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)
  end
end
