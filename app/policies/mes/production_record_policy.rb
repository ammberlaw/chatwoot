class Mes::ProductionRecordPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

Mes::ProductionRecordPolicy.prepend_mod_with('Mes::ProductionRecordPolicy')
