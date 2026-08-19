class Crm::QuotePolicy < ApplicationPolicy
  def index?
    true
  end

  def summary?
    true
  end

  def show?
    true
  end

  def prefill?
    true
  end

  def xlsx?
    true
  end

  def convert_to_sales_order?
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
