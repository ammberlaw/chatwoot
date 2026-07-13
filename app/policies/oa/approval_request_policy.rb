class Oa::ApprovalRequestPolicy < ApplicationPolicy
  # 谁都能发起/查自己相关的审批；具体权限由控制器可见范围与服务校验。
  def index?
    true
  end

  def counts?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def approve?
    true
  end

  def reject?
    true
  end

  def cancel?
    true
  end
end

Oa::ApprovalRequestPolicy.prepend_mod_with('Oa::ApprovalRequestPolicy')
