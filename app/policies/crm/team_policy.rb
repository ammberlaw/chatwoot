class Crm::TeamPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  # 建队/改队/解散仅超级管理员与管理员（deputy_admin）；主管与业务员只读（index/show 只见自己团队）。
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
    @account_user.administrator? || @account_user.crm_role == 'deputy_admin'
  end
end

Crm::TeamPolicy.prepend_mod_with('Crm::TeamPolicy')
