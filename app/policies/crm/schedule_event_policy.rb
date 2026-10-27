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

  # 一键完成跟进（写回跟进记录）：与勾选完成同权。
  def complete_follow_up?
    true
  end

  # 日程待办角标计数：登录用户均可查自己的（数据范围在控制器收口）
  def pending_count?
    true
  end

  # 「今天要做的」：日程 + 各板块待我动手的事。每一类的可见性由 Crm::MyDay 里
  # 各自的权限出口决定（Mes::TodoList / SalesOrderApprover / KpiReminderJob），
  # 这里只管「能不能访问这个接口」。
  # ⚠️ Pundit 按动作名找 policy 方法，少一个就是 500——新增 collection 动作必须同步加这里。
  def my_day?
    true
  end
end
