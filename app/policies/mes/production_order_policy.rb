class Mes::ProductionOrderPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def convert?
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

  def audits?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

Mes::ProductionOrderPolicy.prepend_mod_with('Mes::ProductionOrderPolicy')
