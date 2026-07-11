class Crm::QuotePolicy < ApplicationPolicy
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

Crm::QuotePolicy.prepend_mod_with('Crm::QuotePolicy')
