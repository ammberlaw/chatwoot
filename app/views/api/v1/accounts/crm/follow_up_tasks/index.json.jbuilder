json.meta do
  json.count @tasks_count
  json.current_page params[:page] || 1
end

json.payload do
  json.array! @tasks do |task|
    json.partial! 'api/v1/models/crm_follow_up_task', formats: [:json], resource: task
  end
end
