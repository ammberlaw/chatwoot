class Mes::WarehousePolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:master)
  def update? = @account_user.mes_can?(:master)

  def destroy? = @account_user.administrator?
end

Mes::WarehousePolicy.prepend_mod_with('Mes::WarehousePolicy')
