class Org::DepartmentPolicy < ApplicationPolicy
  # 组织架构人人可看，超级管理员与管理员可维护。
  def index?
    true
  end

  def show?
    true
  end

  def create?
    admin_like?
  end

  def update?
    admin_like?
  end

  def destroy?
    admin_like?
  end

  def reorder?
    admin_like?
  end

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Org::DepartmentPolicy.prepend_mod_with('Org::DepartmentPolicy')
