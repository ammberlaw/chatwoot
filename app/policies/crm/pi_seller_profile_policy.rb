class Crm::PiSellerProfilePolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    true
  end
end

Crm::PiSellerProfilePolicy.prepend_mod_with('Crm::PiSellerProfilePolicy')
