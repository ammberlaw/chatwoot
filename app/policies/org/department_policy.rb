class Org::DepartmentPolicy < ApplicationPolicy
  # 组织架构人人可看，仅管理员可维护。
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

  def reorder?
    @account_user.administrator?
  end
end

Org::DepartmentPolicy.prepend_mod_with('Org::DepartmentPolicy')
