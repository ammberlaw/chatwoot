class Mes::ShipmentPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:shipment)
  def update? = @account_user.mes_can?(:shipment)
  def notify? = @account_user.mes_can?(:shipment)
  def ship? = @account_user.mes_can?(:shipment)

  def destroy? = @account_user.administrator?
end

Mes::ShipmentPolicy.prepend_mod_with('Mes::ShipmentPolicy')
