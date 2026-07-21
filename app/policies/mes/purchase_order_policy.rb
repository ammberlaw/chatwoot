class Mes::PurchaseOrderPolicy < ApplicationPolicy
  def index? = true
  def show? = true
  def requirement? = true

  def create? = @account_user.mes_can?(:purchase)
  def update? = @account_user.mes_can?(:purchase)

  def destroy? = @account_user.administrator?
end

Mes::PurchaseOrderPolicy.prepend_mod_with('Mes::PurchaseOrderPolicy')
