json.payload do
  json.array! @sections do |section|
    json.id section.id
    json.name section.name
    json.viewer_ids section.viewer_ids
    json.viewer_names User.where(id: section.viewer_ids).pluck(:name)
    json.manager_ids section.manager_ids
    json.manager_names User.where(id: section.manager_ids).pluck(:name)
    json.is_default Crm::DocSection::DEFAULT_SECTIONS.include?(section.name)
  end
end
