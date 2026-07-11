class Crm::SalesOrderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def update?
    true
  end

  def attach?
    true
  end

  def detach?
    true
  end

  # 仅管理员可删除（业务员/主管不可删订单——A-CRM 权限口径）。
  def destroy?
    @account_user.administrator?
  end
end

Crm::SalesOrderPolicy.prepend_mod_with('Crm::SalesOrderPolicy')
