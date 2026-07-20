class Mes::PurchaseOrderPolicy < ApplicationPolicy
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

  def requirement?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
