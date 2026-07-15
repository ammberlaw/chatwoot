# 员工薪资配置：薪资敏感，仅超级管理员与管理员（deputy_admin）可读写。
class Crm::EmployeeCompPolicy < ApplicationPolicy
  def index?
    admin_like?
  end

  def show?
    admin_like?
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

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::EmployeeCompPolicy.prepend_mod_with('Crm::EmployeeCompPolicy')
