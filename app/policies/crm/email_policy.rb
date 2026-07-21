class Crm::EmailPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def create?
    true
  end

  def counts?
    true
  end

  def mailboxes?
    true
  end

  def attach_kb?
    true
  end

  def opens?
    true
  end

  def update?
    true
  end

  def destroy?
    @account_user.administrator?
  end
end

Crm::EmailPolicy.prepend_mod_with('Crm::EmailPolicy')
