class Crm::EmailTemplatePolicy < ApplicationPolicy
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
end

Crm::EmailTemplatePolicy.prepend_mod_with('Crm::EmailTemplatePolicy')
