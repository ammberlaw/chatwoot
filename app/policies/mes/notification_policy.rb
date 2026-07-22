class Mes::NotificationPolicy < ApplicationPolicy
  # 仅返回/操作当前用户自己的通知，收件人过滤在控制器完成，故此处放行。
  def index? = true
  def unread_count? = true
  def mark_read? = true
  def mark_all_read? = true
end

Mes::NotificationPolicy.prepend_mod_with('Mes::NotificationPolicy')
