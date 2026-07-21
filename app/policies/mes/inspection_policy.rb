class Mes::InspectionPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = @account_user.mes_can?(:quality)

  def destroy? = @account_user.administrator?
end

Mes::InspectionPolicy.prepend_mod_with('Mes::InspectionPolicy')
