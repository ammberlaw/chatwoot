class Mes::StockBalancePolicy < ApplicationPolicy
  def index?
    true
  end
end

Mes::StockBalancePolicy.prepend_mod_with('Mes::StockBalancePolicy')
