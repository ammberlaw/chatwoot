class Mes::ProductionOrderPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def requirement? = true

  def create? = @account_user.mes_can?(:order)
  def convert? = @account_user.mes_can?(:order)
  def attach_bom? = @account_user.mes_can?(:order)
  def update? = @account_user.mes_can?(:order)

  def destroy? = @account_user.administrator?
end

Mes::ProductionOrderPolicy.prepend_mod_with('Mes::ProductionOrderPolicy')
