class Crm::TeamPolicy < ApplicationPolicy
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

Crm::TeamPolicy.prepend_mod_with('Crm::TeamPolicy')
