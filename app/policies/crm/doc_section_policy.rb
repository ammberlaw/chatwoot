# 资料板块：全员可读（前端渲染板块下拉），仅管理员可配置可见部门。
class Crm::DocSectionPolicy < ApplicationPolicy
  def index?
    true
  end

  def update?
    admin_like?
  end

  def create?
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

Crm::DocSectionPolicy.prepend_mod_with('Crm::DocSectionPolicy')
