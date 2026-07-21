class Mes::SupplierPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?
end

Mes::SupplierPolicy.prepend_mod_with('Mes::SupplierPolicy')
