json.meta do
  json.count @notifications.total_count
  json.current_page params[:page] || 1
  json.unread_count @unread_count
end

json.payload do
  json.array! @notifications do |notification|
    json.partial! 'api/v1/models/mes_notification', formats: [:json], resource: notification
  end
end
