class Mes::SupplierPolicy < ApplicationPolicy
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

  def destroy?
    @account_user.administrator?
  end
end

Mes::SupplierPolicy.prepend_mod_with('Mes::SupplierPolicy')
