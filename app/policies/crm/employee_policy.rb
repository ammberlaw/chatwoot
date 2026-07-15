# 员工档案：含身份证号/薪资/银行卡等敏感信息，仅超级管理员与管理员（deputy_admin）可读写。
class Crm::EmployeePolicy < ApplicationPolicy
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

  def attach?
    admin_like?
  end

  def detach?
    admin_like?
  end

  def audits?
    admin_like?
  end

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Crm::EmployeePolicy.prepend_mod_with('Crm::EmployeePolicy')
