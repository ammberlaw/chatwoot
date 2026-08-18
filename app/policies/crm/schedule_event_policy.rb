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
end
