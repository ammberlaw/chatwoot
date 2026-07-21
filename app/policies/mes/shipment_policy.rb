class Mes::ShipmentPolicy < ApplicationPolicy
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

  def notify?
    true
  end

  def ship?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

Mes::ShipmentPolicy.prepend_mod_with('Mes::ShipmentPolicy')
