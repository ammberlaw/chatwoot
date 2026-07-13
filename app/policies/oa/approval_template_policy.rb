class Oa::ApprovalTemplatePolicy < ApplicationPolicy
  # 审批模板人人可见（发起时要用），仅管理员维护。
  def index?
    true
  end

  def show?
    true
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end

Oa::ApprovalTemplatePolicy.prepend_mod_with('Oa::ApprovalTemplatePolicy')
