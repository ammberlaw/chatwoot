class Mes::BomPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:bom)
  def update? = @account_user.mes_can?(:bom)

  def destroy? = @account_user.administrator?
end

Mes::BomPolicy.prepend_mod_with('Mes::BomPolicy')
