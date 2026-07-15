class Org::MembershipPolicy < ApplicationPolicy
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

  private

  def admin_like?
    @account_user.administrator? || @account_user.crm_deputy_admin?
  end
end

Org::MembershipPolicy.prepend_mod_with('Org::MembershipPolicy')
