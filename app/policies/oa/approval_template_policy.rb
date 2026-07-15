class Oa::ApprovalTemplatePolicy < ApplicationPolicy
  # 列表保持人人可读（发起审批时选模板要用）；
  # 维护（增/改/删）仅管理员与行政部门成员，模板设置页入口也按此隐藏。
  def index?
    true
  end

  def show?
    true
  end

  def create?
    @account_user.oa_template_maintainer?
  end

  def update?
    @account_user.oa_template_maintainer?
  end

  def destroy?
    @account_user.oa_template_maintainer?
  end
end

Oa::ApprovalTemplatePolicy.prepend_mod_with('Oa::ApprovalTemplatePolicy')
