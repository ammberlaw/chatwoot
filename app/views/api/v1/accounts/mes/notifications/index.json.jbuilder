json.meta do
  json.count @notifications.total_count
  json.current_page params[:page] || 1
  json.unread_count @unread_count
  # 各 tab 的未读角标：按全部记录统计，不是只按当前页（前端自己数那 15 条会偏小）。
  json.group_unread do
    Mes::Notification::GROUPS.each { |g| json.set! g, (@group_unread[g] || 0) }
  end
end

json.payload do
  json.array! @notifications do |notification|
    json.partial! 'api/v1/models/mes_notification', formats: [:json], resource: notification
  end
end
