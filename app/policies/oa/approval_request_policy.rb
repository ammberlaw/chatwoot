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

  # 申请人改单：真正的权限在控制器里（只能改自己发起的、且审批中尚无人处理），
  # 这里放行即可。缺了这个方法会落到 ApplicationPolicy#update? = false，
  # 网页端与 App 的「修改」都会 401。
  def update?
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

  # 销假：只能销自己已通过的考勤类单，真正的判定在控制器（revocable? + 申请人本人），
  # 这里放行即可。漏了这个方法不是 403 而是 500（NoMethodError），更难查。
  def revoke?
    true
  end
end

Oa::ApprovalRequestPolicy.prepend_mod_with('Oa::ApprovalRequestPolicy')
