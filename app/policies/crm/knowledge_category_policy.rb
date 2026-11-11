class Crm::KnowledgeCategoryPolicy < ApplicationPolicy
  def recycle_bin?
    true
  end

  def restore?
    true
  end

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
