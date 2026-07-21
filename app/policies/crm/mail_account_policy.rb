class Crm::MailAccountPolicy < ApplicationPolicy
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
    true
  end

  def test?
    true
  end
end

Crm::MailAccountPolicy.prepend_mod_with('Crm::MailAccountPolicy')
