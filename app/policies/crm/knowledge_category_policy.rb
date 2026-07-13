class Crm::KnowledgeCategoryPolicy < ApplicationPolicy
  def index?
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

Crm::KnowledgeCategoryPolicy.prepend_mod_with('Crm::KnowledgeCategoryPolicy')
