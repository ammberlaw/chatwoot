# 员工档案：含身份证号/薪资/银行卡等敏感信息，整对象仅系统管理员可读写。
class Crm::EmployeePolicy < ApplicationPolicy
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

  def attach?
    @account_user.administrator?
  end

  def detach?
    @account_user.administrator?
  end
end

Crm::EmployeePolicy.prepend_mod_with('Crm::EmployeePolicy')
