# 员工薪资配置：薪资敏感，整对象仅系统管理员可读写。
class Crm::EmployeeCompPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
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

Crm::EmployeeCompPolicy.prepend_mod_with('Crm::EmployeeCompPolicy')
