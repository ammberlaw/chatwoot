class Mes::SerialNumberPolicy < ApplicationPolicy
  def index? = true
  def trace? = true

  def create? = @account_user.mes_can?(:stock)

  def destroy? = @account_user.administrator?
end

Mes::SerialNumberPolicy.prepend_mod_with('Mes::SerialNumberPolicy')
