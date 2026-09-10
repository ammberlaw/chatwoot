json.meta do
  json.editable_department_ids(@editable_department_ids == :all ? 'all' : @editable_department_ids)
  json.total_cny @expenses.sum(&:amount_cny)
end

json.payload do
  json.array! @expenses do |expense|
    json.partial! 'api/v1/models/tiktok_expense', formats: [:json], resource: expense
  end
end
