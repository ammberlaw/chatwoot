class Crm::FollowUpTaskPolicy < ApplicationPolicy
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

Crm::FollowUpTaskPolicy.prepend_mod_with('Crm::FollowUpTaskPolicy')
