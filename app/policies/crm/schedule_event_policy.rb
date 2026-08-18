# 日程全员可用；数据范围（本人+被邀）在控制器里收口。
class Crm::ScheduleEventPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def destroy?
    true
  end

  def toggle_done?
    true
  end

  # 日程待办角标计数：登录用户均可查自己的（数据范围在控制器收口）
  def pending_count?
    true
  end
end
